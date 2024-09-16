pub use starknet::{ContractAddress};

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Billing {
    billing_id: felt252,
    amount: u256,
    payment_token: ContractAddress,
    timestamp: u64,
}

#[starknet::interface]
trait IPayment<TContractState> {
    fn get_store_name(self: @TContractState) -> felt252;
    fn get_store_wallet(self: @TContractState) -> ContractAddress;
    fn get_payment_token(self: @TContractState) -> ContractAddress;
    fn get_billing(self: @TContractState, billing_id: felt252) -> Billing;
    fn update_store_name(ref self: TContractState, store_name: felt252);
    fn update_store_wallet_address(ref self: TContractState, store_wallet_address: ContractAddress);
    fn update_payment_token(ref self: TContractState, payment_token: ContractAddress);
    fn pay_billing(
        ref self: TContractState,
        billing_id: felt252,
        payment_token: ContractAddress,
        payment_amount: u256,
    );
}


#[starknet::contract]
pub mod Payment {
    use avs_contract::interfaces::erc20::{IERC20DispatcherTrait, IERC20Dispatcher};
    // use avs_contract::components::owned::{IOwnable, Errors};
    use core::num::traits::Zero;
    use super::{Billing};
    use core::starknet::event::EventEmitter;
    use starknet::{get_caller_address, ContractAddress, get_block_timestamp, get_contract_address};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerWriteAccess,
        StoragePointerReadAccess
    };

    #[storage]
    struct Storage {
        owner: ContractAddress,
        store_name: felt252,
        store_wallet_address: ContractAddress,
        payment_token: ContractAddress,
        billing: Map::<felt252, Billing>,
        total_paid: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        BillingPaid: BillingPaid,
    }

    #[derive(Drop, starknet::Event)]
    struct BillingPaid {
        #[key]
        billing_id: felt252,
        payment_amount: u256,
        payment_token: ContractAddress,
        timestamp: u64,
    }

    pub mod Errors {
        pub const OWNER_ZERO: felt252 = 'Owner address zero';
        pub const NOT_OWNER: felt252 = 'Not the owner';
        pub const NOT_TOKEN_ADDRESS: felt252 = 'Not a token address';
        pub const ZERO_ADDRESS_CALLER: felt252 = 'Caller address zero';
        pub const ZERO_WALLET_ADDRESS: felt252 = 'Wallet address zero';
        pub const ZERO_ADDRESS_TOKEN: felt252 = 'Token address zero';
        pub const ZERO_PAY: felt252 = 'Pay must be > 0';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        store_name: felt252,
        store_wallet_address: ContractAddress,
        payment_token: ContractAddress
    ) {
        assert(Zero::is_non_zero(@store_wallet_address), Errors::OWNER_ZERO);
        assert(Zero::is_non_zero(@payment_token), Errors::ZERO_ADDRESS_TOKEN);
        self.owner.write(get_caller_address());
        self.store_name.write(store_name);
        self.store_wallet_address.write(store_wallet_address);
        self.payment_token.write(payment_token);
        self.total_paid.write(0_u256);
    }

    #[abi(embed_v0)]
    impl Payment of super::IPayment<ContractState> {
        fn get_store_name(self: @ContractState) -> felt252 {
            self.store_name.read()
        }

        fn get_store_wallet(self: @ContractState) -> ContractAddress {
            self.store_wallet_address.read()
        }

        fn get_payment_token(self: @ContractState) -> ContractAddress {
            self.payment_token.read()
        }

        fn get_billing(self: @ContractState, billing_id: felt252) -> Billing {
            self.billing.read((billing_id))
        }

        fn update_store_name(ref self: ContractState, store_name: felt252) {
            let owner = self.owner.read();
            assert(owner == get_caller_address(), Errors::NOT_OWNER);
            self.store_name.write(store_name)
        }

        fn update_store_wallet_address(
            ref self: ContractState, store_wallet_address: ContractAddress
        ) {
            let owner = self.owner.read();
            assert(owner == get_caller_address(), Errors::NOT_OWNER);
            self.store_wallet_address.write(store_wallet_address)
        }

        fn update_payment_token(ref self: ContractState, payment_token: ContractAddress) {
            let owner = self.owner.read();
            assert(owner == get_caller_address(), Errors::NOT_OWNER);
            self.payment_token.write(payment_token);
        }

        fn pay_billing(
            ref self: ContractState,
            billing_id: felt252,
            payment_token: ContractAddress,
            payment_amount: u256,
        ) {
            assert(payment_token == self.payment_token.read(), Errors::NOT_TOKEN_ADDRESS);
            assert(payment_amount > 0, Errors::ZERO_PAY);
            let sender = get_contract_address();
            let payment_token_contract = IERC20Dispatcher { contract_address: payment_token };
            let timestamp = get_block_timestamp();

            payment_token_contract.transferFrom(get_caller_address(), sender, payment_amount);

            let billing = Billing { billing_id, amount: payment_amount, payment_token, timestamp };

            self.emit(BillingPaid { billing_id, payment_token, payment_amount, timestamp });
            self.billing.write(billing_id, billing);
        }
    }
}
