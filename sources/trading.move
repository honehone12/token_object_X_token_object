module token_object_x_token_object::trading {
    use std::signer;
    use std::vector;
    use std::error;
    use std::string::String;
    use std::option::{Self, Option};
    use aptos_framework::object::{
        Self,
        Object,
        ConstructorRef, 
        TransferRef,
    };
    use aptos_token_objects::token;

    const E_TRADING_DISABLED: u64 = 1;
    const E_NOT_MATCHED: u64 = 2;
    const E_NOT_OWNER: u64 = 3;

    struct Trading has key {
        transfer_ref: Option<TransferRef>, // none means disabled forever
        matching_collection: vector<String>, // empty means currently disabled
        matching_tokens: vector<String>, // empty means currently disabled
        match_all_tokens_in_collections: bool // still need collection names
    }

    fun init_trading(constructor_ref: &ConstructorRef) {
        let obj_signer = object::generate_signer(constructor_ref);
        let transfer = object::generate_transfer_ref(constructor_ref);
        move_to(
            &obj_signer,
            Trading{
                transfer_ref: option::some(transfer),
                matching_collection: vector::empty(),
                matching_tokens: vector::empty(),
                match_all_tokens_in_collections: false
            }
        );
    }

    fun freeze_trading<T: key>(owner: &signer, object: Object<T>)
    acquires Trading {
        assert!(
            object::is_owner(object, signer::address_of(owner)), 
            error::permission_denied(E_NOT_OWNER)
        );
        let trading = borrow_global_mut<Trading>(object::object_address(&object));
        _ = option::extract(&mut trading.transfer_ref);   
    }

    fun add_matching_names<T: key>(
        owner: &signer,
        object: Object<T>,
        matching_collection_names: vector<String>,
        matching_token_names: vector<String>
    )
    acquires Trading {
        assert!(
            object::is_owner(object, signer::address_of(owner)), 
            error::permission_denied(E_NOT_OWNER)
        );
        let trading = borrow_global_mut<Trading>(object::object_address(&object));
        // reverse is cheaper
        // want duplication check?
        vector::reverse_append(&mut trading.matching_collection, matching_collection_names);
        vector::reverse_append(&mut trading.matching_tokens, matching_token_names);   
        trading.match_all_tokens_in_collections = false;
    }

    fun clear_matching_names<T: key>(owner: &signer, object: Object<T>)
    acquires Trading {
        assert!(
            object::is_owner(object, signer::address_of(owner)), 
            error::permission_denied(E_NOT_OWNER)
        );
        let trading = borrow_global_mut<Trading>(object::object_address(&object));
        trading.matching_collection = vector::empty();
        trading.matching_tokens = vector::empty();
        trading.match_all_tokens_in_collections = false;   
    }

    fun set_matching_all_tokens_in_collections<T: key>(owner: &signer, object: Object<T>)
    acquires Trading {
        assert!(
            object::is_owner(object, signer::address_of(owner)), 
            error::permission_denied(E_NOT_OWNER)
        );
        let trading = borrow_global_mut<Trading>(object::object_address(&object));
        assert!(
            vector::length(&trading.matching_collection) > 0,
            error::invalid_argument(E_TRADING_DISABLED)
        );
        trading.matching_tokens = vector::empty();
        trading.match_all_tokens_in_collections = true;
    }

    fun flash_offer<T1: key, T2: key>(
        offerer: &signer, 
        object_to_offer: Object<T1>, 
        target_object: Object<T2>
    )
    acquires Trading {
        let offerer_address = signer::address_of(offerer);
        assert!(
            object::is_owner(object_to_offer, offerer_address), 
            error::permission_denied(E_NOT_OWNER)
        );

        if (exists<Trading>(object::object_address(&object_to_offer))) {
            clear_matching_names(offerer, object_to_offer);
        };

        let target_trading = borrow_global_mut<Trading>(object::object_address(&target_object));
        assert!(
            option::is_some(&target_trading.transfer_ref), 
            error::unavailable(E_TRADING_DISABLED)
        );
        let collection = token::collection(object_to_offer);
        assert!(
            vector::contains(&target_trading.matching_collection, &collection), 
            error::invalid_argument(E_NOT_MATCHED)
        );
        if (!target_trading.match_all_tokens_in_collections) {
            let token = token::name(object_to_offer);
            assert!(
                vector::contains(&target_trading.matching_tokens, &token), 
                error::invalid_argument(E_NOT_MATCHED)
            );
        };

        target_trading.matching_collection = vector::empty();
        target_trading.matching_tokens = vector::empty();
        target_trading.match_all_tokens_in_collections = false;

        let target_owner_address = object::owner(target_object);
        object::transfer(offerer, object_to_offer, target_owner_address);
        let linear_transfer = object::generate_linear_transfer_ref(option::borrow(&target_trading.transfer_ref));
        object::transfer_with_ref(linear_transfer, offerer_address);
    }
}