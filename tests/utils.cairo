use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;

pub const OWNER: ContractAddress = 'owner'.try_into().unwrap();
pub const USER1: ContractAddress = 'user1'.try_into().unwrap();

fn deploy_contract(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

pub fn deploy_swapx_contract(owner: ContractAddress) -> ContractAddress {
    let mut calldata = array![];
    owner.serialize(ref calldata);

    deploy_contract("SwapX", calldata)
}
