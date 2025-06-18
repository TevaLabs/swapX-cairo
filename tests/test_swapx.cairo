use core::num::traits::Zero;
use snforge_std::{
    EventSpyAssertionsTrait, spy_events, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use swapx::interfaces::iswapx::{ISwapXDispatcher, ISwapXDispatcherTrait};
use swapx::swapx::SwapX::{Event, TokenSupported};
use super::utils::{OWNER, USER1, deploy_swapx_contract};

#[test]
fn test_add_supported_tokens_as_admin() {
    let owner = OWNER;

    // Deploy contract
    let swapx_address = deploy_swapx_contract(owner);
    let swapx = ISwapXDispatcher { contract_address: swapx_address };

    let token_address: ContractAddress = 'token'.try_into().unwrap();

    // Owner with admin role whitelist token address
    start_cheat_caller_address(swapx_address, owner);
    let mut spy = spy_events();

    swapx.add_supported_token(token_address);
    stop_cheat_caller_address(swapx_address);

    // Verify the token address is now supported
    let is_supported = swapx.is_token_supported(token_address);
    assert(is_supported, 'Token should be supported');

    // Check that an event has been emitted
    let event = Event::TokenSupported(TokenSupported { token_address });
    spy.assert_emitted(@array![(swapx_address, event)]);
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_add_supported_tokens_as_non_owner() {
    let owner = OWNER;
    let user = USER1;

    // Deploy contract
    let swapx_address = deploy_swapx_contract(owner);
    let swapx = ISwapXDispatcher { contract_address: swapx_address };

    let token_address: ContractAddress = 'token'.try_into().unwrap();

    // Non-admin user attempts to whitelist token address
    start_cheat_caller_address(swapx_address, user);
    swapx.add_supported_token(token_address);
    stop_cheat_caller_address(swapx_address);
}

#[test]
#[should_panic(expected: 'Token address cannot be zero')]
fn test_add_supported_tokens_with_zero_token_address() {
    let owner = OWNER;

    // Deploy contract
    let swapx_address = deploy_swapx_contract(owner);
    let swapx = ISwapXDispatcher { contract_address: swapx_address };

    let token_address: ContractAddress = Zero::zero();

    // Owner with admin role attempts to whitelist zero token address
    start_cheat_caller_address(swapx_address, owner);
    swapx.add_supported_token(token_address);
    stop_cheat_caller_address(swapx_address);
}
