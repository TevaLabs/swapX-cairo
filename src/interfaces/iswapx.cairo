use starknet::ContractAddress;

#[starknet::interface]
pub trait ISwapX<TContractState> {
    fn add_supported_token(ref self: TContractState, token_address: ContractAddress);
    fn is_token_supported(self: @TContractState, token_address: ContractAddress) -> bool;
    fn deposit(ref self: TContractState, token_address: ContractAddress, amount: u256);
    fn get_user_token_balance(self: @TContractState, user: ContractAddress, token_address: ContractAddress) -> u256;
}

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256);
}