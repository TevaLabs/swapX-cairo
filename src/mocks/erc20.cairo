use starknet::ContractAddress;

#[starknet::interface]
pub trait IMintable<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    // fn approve( ref self: TContractState, spender: ContractAddress, amount: u256,
    // ) -> bool;
    // fn balance_of(ref self: TContractState, account: ContractAddress) -> u256;
}

#[starknet::contract]
pub mod ERC20 {
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::{ContractAddress};
    use super::IMintable;


    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // External
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    // Internal
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.erc20.initializer("SwapX", "SWX");
        self.ownable.initializer(owner);

        // mint some tokens to the owner
        let supply: u256 = 5_000_000_000_000; //
        self.erc20.mint(owner, supply);
    }

    #[abi(embed_v0)]
    impl MintableImpl of IMintable<ContractState> {
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.erc20.mint(recipient, amount);
        }

        // fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
        //     self.erc20.approve(spender, amount)
        // }

        // fn balance_of(ref self: ContractState, account: ContractAddress) -> u256 {
        //     self.erc20.balance_of(account)
        // }
    }
}