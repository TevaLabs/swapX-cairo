#[starknet::contract]
pub mod SwapX {
    use core::num::traits::Zero;
    use ekubo::components::shared_locker::{
        call_core_with_callback, consume_callback_data, handle_delta,
    };
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker, SwapParameters};
    use ekubo::types::delta::Delta;
    use ekubo::types::i129::i129;
    use ekubo::types::keys::PoolKey;
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use swapx::errors::Errors;
    use swapx::interfaces::iswapx::{IERC20Dispatcher, IERC20DispatcherTrait, ISwapX};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    /// AccessControl
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;


    #[derive(Copy, Serde, Drop)]
    pub struct SwapData {
        pub params: SwapParameters,
        pub pool_key: PoolKey,
        pub caller: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        TokenSupported: TokenSupported,
        MerchantPaid: MerchantPaid,
        TokenSwapped: TokenSwapped,
    }

    /// Emitted when a token is whitelisted
    #[derive(Drop, starknet::Event)]
    pub struct TokenSupported {
        pub token_address: ContractAddress,
    }


    /// This event is emitted when a user successfully pays a merchant with a supported token
    #[derive(Drop, starknet::Event)]
    pub struct MerchantPaid {
        pub user: ContractAddress,
        pub merchant: ContractAddress,
        pub token_address: ContractAddress,
        pub amount: u256,
    }


    #[derive(Drop, starknet::Event)]
    struct TokenSwapped {
        user: ContractAddress,
        token_in: ContractAddress,
        token_out: ContractAddress,
        amount_in: u256,
        amount_out: u256,
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // Maps token addresses to supported status
        pub supported_tokens: Map<ContractAddress, bool>,
        pub balance: Map<(ContractAddress, ContractAddress), u256>,
        // liquidity_pools: Map<ContractAddress, u256>,
        ekubo_core: ICoreDispatcher,
    }


    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress, ekubo_core: ICoreDispatcher) {
        // AccessControl initialization
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, admin);

        self.ekubo_core.write(ekubo_core);
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        fn swap(ref self: ContractState, swap_data: SwapData) -> Delta {
            // https://github.com/EkuboProtocol/abis/blob/main/src/components/shared_locker.cairo
            call_core_with_callback(self.ekubo_core.read(), @swap_data)
        }
    }

    #[abi(embed_v0)]
    impl SwapXImpl of ISwapX<ContractState> {
        /// Admin-only: adds `token_address` to the supported tokens list
        fn add_supported_token(ref self: ContractState, token_address: ContractAddress) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);

            assert(token_address.is_non_zero(), Errors::ZERO_TOKEN_ADDRESS);

            self.supported_tokens.entry(token_address).write(true);
            self.emit(TokenSupported { token_address });
        }

        /// Returns whether `token_address` is supported
        fn is_token_supported(self: @ContractState, token_address: ContractAddress) -> bool {
            self.supported_tokens.entry(token_address).read()
        }

        fn swap_token_to_stable(
            ref self: ContractState,
            token_in: ContractAddress,
            token_out: ContractAddress,
            amount_in: u256,
        ) {
            // Check if the input amount is valid
            assert(amount_in.is_non_zero(), Errors::INVALID_AMOUNT);

            let user: ContractAddress = get_caller_address();
            let contract: ContractAddress = get_contract_address();

            // Verify user has sufficient balance of `token_in` in the contract
            let user_balance_in = self.balance.entry((user, token_in)).read();
            assert(user_balance_in >= amount_in, Errors::INSUFFICIENT_BALANCE);

            // Check if the tokens are supported
            let token_in_is_supported: bool = self.is_token_supported(token_in);
            assert(token_in_is_supported, Errors::UNSUPPORTED_TOKEN);
            // Check if the output token is supported
            // `token_out` will be used to pay the merchant, or withdrawn later by the user
            let token_out_is_supported: bool = self.is_token_supported(token_out);
            assert(token_out_is_supported, Errors::UNSUPPORTED_TOKEN);

            // Construct PoolKey
            // Sort the tokens
            let (token0, token1) = if token_in < token_out {
                (token_in, token_out)
            } else {
                (token_out, token_in)
            };
            let pool_key = PoolKey {
                token0: token0,
                token1: token1,
                fee: 100663296, // 0.3% fee (0.3 / 100 * 2^128)
                tick_spacing: 1000, // 0.1% tick spacing
                extension: 0.try_into().unwrap(),
            };

            // Construct SwapParameters (exact-input swap)
            let is_token1 = token_in == token1;
            let params = SwapParameters {
                amount: i129 {
                    mag: amount_in.try_into().unwrap(), sign: false,
                }, // Positive for exact-input
                is_token1: is_token1,
                sqrt_ratio_limit: 18446748437148339061, // min sqrt ratio limit
                skip_ahead: 0,
            };

            let delta = self
                .swap(SwapData { params: params, pool_key: pool_key, caller: contract });

            // when delta sign is negative, it means the token is token_out
            let (token_in, token_out, amount_in, amount_out) = if delta.amount0.sign {
                (pool_key.token1, pool_key.token0, delta.amount1.mag, delta.amount0.mag)
            } else {
                (pool_key.token0, pool_key.token1, delta.amount0.mag, delta.amount1.mag)
            };

            // Update the user's balances
            let new_balance_in = user_balance_in - amount_in.into();
            self.balance.entry((user, token_in)).write(new_balance_in);

            let user_balance_out = self.balance.entry((user, token_out)).read();
            let new_balance_out = user_balance_out + amount_out.into();
            self.balance.entry((user, token_out)).write(new_balance_out);

            // Emit an event for successful swap
            self
                .emit(
                    TokenSwapped {
                        user,
                        token_in,
                        token_out,
                        amount_in: amount_in.into(),
                        amount_out: amount_out.into(),
                    },
                );
        }
    }

    //This function will only work when the amount is less than or equal to the user's balance for
    //that token.
    //It will transfer the amount to the merchant and emit an event.
    pub fn transfer_to_merchant(
        ref self: ContractState,
        token_address: ContractAddress,
        merchant: ContractAddress,
        amount: u256,
    ) {
        let user: ContractAddress = get_caller_address();
        let balance: u256 = self.balance.entry((user, token_address)).read();
        let token_is_supported: bool = self.is_token_supported(token_address);

        // Check if the user has enough balance and the token is supported and if the users balance
        // is sufficient for the transfer.
        if amount <= balance && token_is_supported {
            let new_balance = balance - amount;
            self.balance.entry((user, token_address)).write(new_balance);

            //During testing I excluded this part, since its implementation is not provided.
            //So when testing, comment this part out and it will work as expected.
            let dispatcher = IERC20Dispatcher { contract_address: token_address };
            dispatcher.transfer(merchant, amount);

            self.emit(MerchantPaid { user, merchant, token_address, amount });
        }
    }


    #[abi(embed_v0)]
    impl Locker of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.ekubo_core.read();
            ekubo::components::shared_locker::check_caller_is_core(core);

            let SwapData { pool_key, params, caller } = consume_callback_data(core, data);
            let delta = core.swap(pool_key, params);

            handle_delta(core, pool_key.token0, delta.amount0, caller);
            handle_delta(core, pool_key.token1, delta.amount1, caller);

            let mut arr: Array<felt252> = ArrayTrait::new();
            Serde::serialize(@delta, ref arr);
            arr.span()
        }
    }
}
