#[starknet::contract]
pub mod SwapX {
    use core::num::traits::Zero;
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use swapx::errors::Errors;
    use swapx::interfaces::iswapx::{ISwapX, IERC20Dispatcher, IERC20DispatcherTrait};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    /// AccessControl
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        TokenSupported: TokenSupported,
        MerchantPaid:MerchantPaid,
        TokenDeposited: TokenDeposited,
    }

    /// Emitted when a token is whitelisted
    #[derive(Drop, starknet::Event)]
    pub struct TokenSupported {
        pub token_address: ContractAddress,
    }

    /// Emitted when a user deposits token into the contract
    #[derive(starknet::Event, Drop)]
    pub struct TokenDeposited {
        pub user: ContractAddress,
        pub token_address: ContractAddress,
        pub amount: u256,
    }

    
    /// This event is emitted when a user successfully pays a merchant with a supported token
    #[derive(Drop, starknet::Event)]
    pub struct MerchantPaid {
        pub user: ContractAddress,
        pub merchant: ContractAddress,
        pub token_address: ContractAddress,
        pub amount: u256
    } 

    #[storage]
    struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // Maps token addresses to supported status
        pub supported_tokens: Map<ContractAddress, bool>,
        pub balance: Map<(ContractAddress, ContractAddress), u256> 
    }


    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        // AccessControl initialization
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, admin);
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

        /// Allows users to deposit tokens into the contract
        fn deposit(ref self: ContractState, token_address: ContractAddress, amount: u256) {
            let depositor: ContractAddress = get_caller_address();
            let contract: ContractAddress = get_contract_address();
            let token_is_supported: bool = self.is_token_supported(token_address);
    
            // Check if the token is in the supported tokens list
            assert(token_is_supported, Errors::UNSUPPORTED_TOKEN);
    
            assert(amount.is_non_zero(), Errors::INVALID_AMOUNT);
    
            // Transfer the tokens from the user to the contract
            // Note: The depositor must approve the contract to spend at least `amount` of tokens
            // Note: The depositor must have enough balance to cover the `amount`
            let token_dispatcher = ERC20ABIDispatcher { contract_address: token_address };
            token_dispatcher.transfer_from(depositor, contract, amount);
    
            // Update the user's balance for the token
            let user_current_balance = self.balance.entry((depositor, token_address)).read();
            let new_balance = user_current_balance + amount;
            self.balance.entry((depositor, token_address)).write(new_balance);
    
            // TODO: (Optional) Update liquidity pool
            // state variable: // liquidity_pools: Map<ContractAddress, u256>
    
            // Emit an event for successful deposit
            self.emit(TokenDeposited { user: depositor, token_address, amount });
        }

        // Retrieves the balance for a specific user and token
        fn get_user_token_balance(self: @ContractState, user: ContractAddress, token_address: ContractAddress) -> u256 {
            self.balance.entry((user, token_address)).read()
        }
    }

    //This function will only work when the amount is less than or equal to the user's balance for that token.
    //It will transfer the amount to the merchant and emit an event.
    pub  fn transfer_to_merchant(
        ref self: ContractState,
        token_address: ContractAddress,
        merchant: ContractAddress,
        amount: u256
    ) {
        let user: ContractAddress = get_caller_address();
        let balance: u256 = self.balance.entry((user, token_address)).read();
        let token_is_supported: bool = self.is_token_supported(token_address);

        // Check if the user has enough balance and the token is supported and if the users balance is sufficient
        // for the transfer.
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
}
