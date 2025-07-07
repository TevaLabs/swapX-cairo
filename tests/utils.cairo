use openzeppelin_token::erc20::interface::ERC20ABIDispatcher;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use swapx::mocks::erc20::IMintableDispatcher;

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

pub fn deploy_mock_erc20() -> IMintableDispatcher {
    let owner = OWNER;
    let contract_class = declare("ERC20").unwrap().contract_class();
    let mut constructor_args: Array<felt252> = array![];
    owner.serialize(ref constructor_args);
    let (contract_address, _) = contract_class.deploy(@constructor_args).unwrap();

    IMintableDispatcher { contract_address: contract_address }
}
