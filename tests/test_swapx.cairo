use core::num::traits::Zero;
use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    EventSpyAssertionsTrait, EventSpyTrait, spy_events, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;
use swapx::interfaces::iswapx::{ISwapXDispatcher, ISwapXDispatcherTrait};
use swapx::mocks::erc20::IMintableDispatcherTrait;
use swapx::swapx::SwapX;
use swapx::swapx::SwapX::{Event, TokenSupported};
use super::utils::{OWNER, USER1, deploy_mock_erc20, deploy_swapx_contract};

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

#[should_panic(expected: 'Caller is missing role')]
#[test]
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

#[should_panic(expected: 'Token address cannot be zero')]
#[test]
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

#[test]
fn test_deposit_success() {
    // Deploy contracts
    let owner: ContractAddress = OWNER;
    let depositor: ContractAddress = USER1;
    let swapx_address = deploy_swapx_contract(owner);
    let swapx = ISwapXDispatcher { contract_address: swapx_address };
    let eth_dispatcher = deploy_mock_erc20();
    let eth_address = eth_dispatcher.contract_address;
    let erc20 = ERC20ABIDispatcher { contract_address: eth_address };
    let mint_amount = 2_000_u256;
    let deposit_amount = 700_u256;

    // Prepare user for deposit
    start_cheat_caller_address(eth_address, owner);
    eth_dispatcher.mint(depositor, mint_amount);
    stop_cheat_caller_address(eth_address);

    // Approve spender to use tokens
    start_cheat_caller_address(eth_address, depositor);
    erc20.approve(swapx_address, deposit_amount);
    stop_cheat_caller_address(eth_address);

    // Owner with admin role whitelist token address
    start_cheat_caller_address(swapx_address, owner);
    swapx.add_supported_token(eth_address);
    stop_cheat_caller_address(swapx_address);

    // User deposits into SwapX
    let mut spy = spy_events();
    start_cheat_caller_address(swapx_address, depositor);
    swapx.deposit(eth_address, deposit_amount);
    stop_cheat_caller_address(swapx_address);

    // Check user balance in SwapX
    let balance = swapx.get_user_token_balance(depositor, eth_address);
    assert(balance == deposit_amount, 'Deposit failed');

    // Verify event emission
    let events = spy.get_events();
    assert(
        events.events.len() == 3, 'Expected three events',
    ); // TokenSupported, TokenDeposited and Transfer

    let expected_deposited_event = SwapX::Event::TokenDeposited(
        SwapX::TokenDeposited {
            user: depositor, token_address: eth_address, amount: deposit_amount,
        },
    );
    let expected_events = array![(swapx_address, expected_deposited_event)];
    spy.assert_emitted(@expected_events);
}

#[should_panic(expected: 'Amount cannot be zero')]
#[test]
fn test_deposit_zero_amount_fails() {
    let owner = OWNER;
    let depositor = USER1;
    let mint_amount = 1000_u256;

    // Deploy contract
    let swapx_address = deploy_swapx_contract(owner);
    let swapx = ISwapXDispatcher { contract_address: swapx_address };
    let eth_dispatcher = deploy_mock_erc20();
    let erc20 = ERC20ABIDispatcher { contract_address: eth_dispatcher.contract_address };
    let eth_address = eth_dispatcher.contract_address;

    // Prepare user for deposit
    start_cheat_caller_address(eth_address, owner);
    eth_dispatcher.mint(depositor, mint_amount);
    stop_cheat_caller_address(eth_address);

    // Approve spender to use tokens
    start_cheat_caller_address(eth_address, depositor);
    erc20.approve(swapx_address, 1000_u256);
    stop_cheat_caller_address(eth_address);

    // Owner with admin role whitelist token address
    start_cheat_caller_address(swapx_address, owner);
    swapx.add_supported_token(eth_address);
    stop_cheat_caller_address(swapx_address);

    // User attempts to deposit zero amount
    start_cheat_caller_address(swapx_address, depositor);
    swapx.deposit(eth_address, 0_u256);
    stop_cheat_caller_address(swapx_address);
}

#[should_panic(expected: 'Token is not supported')]
#[test]
fn test_deposit_unsupported_token_fails() {
    let owner = OWNER;
    let depositor = USER1;

    // Deploy contract
    let swapx_address = deploy_swapx_contract(owner);
    let swapx = ISwapXDispatcher { contract_address: swapx_address };
    let eth_dispatcher = deploy_mock_erc20();
    let eth_address = eth_dispatcher.contract_address;
    let erc20 = ERC20ABIDispatcher { contract_address: eth_address };

    // Prepare user for deposit
    start_cheat_caller_address(eth_address, owner);
    eth_dispatcher.mint(depositor, 1000_u256);
    stop_cheat_caller_address(eth_address);

    // Approve spender to use tokens
    start_cheat_caller_address(eth_address, depositor);
    erc20.approve(swapx_address, 1000_u256);
    stop_cheat_caller_address(eth_address);

    // User attempts to deposit unsupported token
    start_cheat_caller_address(swapx_address, depositor);
    swapx.deposit(eth_address, 500_u256); // Eth is not supported yet
    stop_cheat_caller_address(swapx_address);
}

#[should_panic(expected: 'ERC20: insufficient balance')]
#[test]
fn test_deposit_insufficient_token_balance_fails() {
    let owner = OWNER;
    let depositor = USER1;
    let mint_amount = 1000_u256;
    let deposit_amount = 1100_u256;
    let allowance_amount = 2000_u256;

    // Deploy contract
    let swapx_address = deploy_swapx_contract(owner);
    let swapx = ISwapXDispatcher { contract_address: swapx_address };
    let eth_dispatcher = deploy_mock_erc20();
    let eth_address = eth_dispatcher.contract_address;
    let erc20 = ERC20ABIDispatcher { contract_address: eth_address };

    // Prepare user for deposit
    start_cheat_caller_address(eth_address, owner);
    eth_dispatcher.mint(depositor, mint_amount);
    stop_cheat_caller_address(eth_address);

    // Approve spender to use tokens
    start_cheat_caller_address(eth_address, depositor);
    erc20.approve(swapx_address, allowance_amount); // Approve more than deposit amount
    stop_cheat_caller_address(eth_address);

    // Owner with admin role whitelist token address
    start_cheat_caller_address(swapx_address, owner);
    swapx.add_supported_token(eth_address);
    stop_cheat_caller_address(swapx_address);

    // User attempts to deposit more than balance
    start_cheat_caller_address(swapx_address, depositor);
    swapx.deposit(eth_address, deposit_amount); // user has 100 tokens less
    stop_cheat_caller_address(swapx_address);
}

#[should_panic(expected: 'ERC20: insufficient allowance')]
#[test]
fn test_deposit_insufficient_allowance_fails() {
    let owner = OWNER;
    let depositor = USER1;

    // Deploy contract
    let swapx_address = deploy_swapx_contract(owner);
    let swapx = ISwapXDispatcher { contract_address: swapx_address };
    let eth_dispatcher = deploy_mock_erc20();
    let eth_address = eth_dispatcher.contract_address;
    let erc20 = ERC20ABIDispatcher { contract_address: eth_address };

    // Prepare user for deposit
    start_cheat_caller_address(eth_address, owner);
    eth_dispatcher.mint(depositor, 1000_u256);
    stop_cheat_caller_address(eth_address);

    // Approve spender to use tokens
    start_cheat_caller_address(eth_address, depositor);
    erc20.approve(swapx_address, 500_u256); // Only approve 500
    stop_cheat_caller_address(eth_address);

    // Owner with admin role whitelist token address
    start_cheat_caller_address(swapx_address, owner);
    swapx.add_supported_token(eth_address);
    stop_cheat_caller_address(swapx_address);

    // User attempts to deposit more than allowance
    start_cheat_caller_address(swapx_address, depositor);
    swapx.deposit(eth_address, 600_u256); // User only allowed 500 tokens
    stop_cheat_caller_address(swapx_address);
}
