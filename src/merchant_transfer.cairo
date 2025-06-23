#[starknet::contract]
pub mod MerchantTransfer {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
    use swapx::interfaces::iswapx::{IERC20Dispatcher, IERC20DispatcherTrait};
    

    #[storage]
    pub struct Storage {
        //This maps the user's balance for each token address
        // The key is a tuple of (user_address, token_address)
        //The value is the balance of that user for the token
        
        pub balance: Map<(ContractAddress, ContractAddress), u256> 
    }
    

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event{
        MerchantPaid:MerchantPaid
    }
    
    #[derive(Drop, starknet::Event)]
    pub struct MerchantPaid {
        pub user: ContractAddress,
        pub merchant: ContractAddress,
        pub token_address: ContractAddress,
        pub amount: u256
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

        if amount <= balance {
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


#[cfg(test)]
mod tests {
    use starknet::{ContractAddress, get_caller_address, contract_address_const};
    use snforge_std::{
    EventSpyAssertionsTrait, spy_events,test_address
    };
    use starknet::storage::{StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
    
    use swapx::merchant_transfer::MerchantTransfer::{transfer_to_merchant, MerchantPaid};
    use swapx::merchant_transfer::MerchantTransfer;
   
    /// Test for the transfer_to_merchant function is working properly.
    #[test]
    fn transfer_to_merchant_test() {
        // Setup
        let user: ContractAddress = get_caller_address();
        let merchant: ContractAddress = contract_address_const::<0x5678>();
        let token_address: ContractAddress = contract_address_const::<0x9abc>();
        let amount: u256 = 100;

        // Initialize storage with some balance
        let mut state = MerchantTransfer::contract_state_for_testing();
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
        let merchant: ContractAddress = contract_address_const::<0x5678>();
        let token_address: ContractAddress = contract_address_const::<0x9abc>();
        let amount: u256 = 200; // More than the balance

        // Initialize storage with some balance less than the transfer amount
        // to ensure that it doesn't allow the transfer
        let mut state = MerchantTransfer::contract_state_for_testing();
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
        let merchant: ContractAddress = contract_address_const::<0x5678>();
        let token_address: ContractAddress = contract_address_const::<0x9abc>();
        let amount: u256 = 100;
        let test_contract_address: ContractAddress = test_address();

        
        let mut spy = spy_events();
        let mut state = MerchantTransfer::contract_state_for_testing();
        state.balance.entry((user, token_address)).write(200);

        
        

        // Call the transfer function
        transfer_to_merchant(ref state, token_address, merchant, amount);

        // Check that the MerchantPaid event was emitted
        spy
            .assert_emitted(
                @array![(
                    test_contract_address,
                    MerchantTransfer::Event::MerchantPaid(
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
}