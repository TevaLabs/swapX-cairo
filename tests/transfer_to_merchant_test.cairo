use starknet::{ContractAddress, get_caller_address};
use snforge_std::{
    EventSpyAssertionsTrait, spy_events,test_address
};
use starknet::storage::{StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
    
use swapx::swapx::SwapX::{transfer_to_merchant, MerchantPaid};
use swapx::swapx::SwapX;
   
/// Test for the transfer_to_merchant function is working properly.
#[test]
fn transfer_to_merchant_test() {
    // Setup
    let user: ContractAddress = get_caller_address();
    let merchant: ContractAddress = 0x5678.try_into().unwrap();
    let token_address: ContractAddress = 0x9abc.try_into().unwrap();
    let amount: u256 = 100;

    // Initialize storage with some balance
    let mut state = SwapX::contract_state_for_testing();
    state.supported_tokens.entry(token_address).write(true);
    state.balance.entry((user, token_address)).write(200);

    // Call the transfer function
    transfer_to_merchant(ref state, token_address, merchant, amount);

     // Check the balance after transfer
    let new_balance = state.balance.entry((user, token_address)).read();
    assert!(new_balance == 100, "Balance should be reduced by the transfer amount");
}


/// This test checks that the transfer function does not allow a transfer if the user has insufficient balance.
#[test]
fn transfer_to_merchant_insufficient_balance_test() {
    // Setup
    let user: ContractAddress = get_caller_address();
    let merchant: ContractAddress = 0x5678.try_into().unwrap();
    let token_address: ContractAddress = 0x9abc.try_into().unwrap();
    let amount: u256 = 200; // More than the balance

    // Initialize storage with some balance less than the transfer amount
    // to ensure that it doesn't allow the transfer
    let mut state = SwapX::contract_state_for_testing();
    state.supported_tokens.entry(token_address).write(true);
    state.balance.entry((user, token_address)).write(100);

     // Call the transfer function
    transfer_to_merchant(ref state, token_address, merchant, amount);

    // Check the balance remains unchanged
    let new_balance = state.balance.entry((user, token_address)).read();
    assert!(new_balance == 100, "Balance should remain unchanged due to insufficient funds");
}


/// This test checks that the MerchantPaid event is emitted correctly when a transfer is made to a merchant.
#[test]
fn transfer_to_merchant_event_test() {
    // Setup
    let user: ContractAddress = get_caller_address();
    let merchant: ContractAddress = 0x5678.try_into().unwrap();
    let token_address: ContractAddress = 0x9abc.try_into().unwrap();
    let amount: u256 = 100;
    let test_contract_address: ContractAddress = test_address();

        
    let mut spy = spy_events();
    let mut state = SwapX::contract_state_for_testing();
    state.supported_tokens.entry(token_address).write(true);
    state.balance.entry((user, token_address)).write(200);

        
        

    // Call the transfer function
    transfer_to_merchant(ref state, token_address, merchant, amount);

    // Check that the MerchantPaid event was emitted
    spy
        .assert_emitted(
            @array![(
                test_contract_address,
                SwapX::Event::MerchantPaid(
                    MerchantPaid{
                        user,
                        merchant,
                        token_address,
                        amount
                    }
                ),
            )]
        );     
}
