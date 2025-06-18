#[starknet::contract]
pub mod SwapX {
    use core::num::traits::Zero;
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use swapx::errors::Errors;
    use swapx::interfaces::iswapx::ISwapX;

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
    }

    /// Emitted when a token is whitelisted
    #[derive(Drop, starknet::Event)]
    pub struct TokenSupported {
        pub token_address: ContractAddress,
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // Maps token addresses to supported status
        supported_tokens: Map<ContractAddress, bool>,
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
    }
}
