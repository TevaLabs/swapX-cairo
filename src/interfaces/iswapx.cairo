use starknet::ContractAddress;

#[starknet::interface]
pub trait ISwapX<TContractState> {
    fn add_supported_token(ref self: TContractState, token_address: ContractAddress);
    fn is_token_supported(self: @TContractState, token_address: ContractAddress) -> bool;
}
