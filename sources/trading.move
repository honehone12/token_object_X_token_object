module tradable_token_objects::trading {
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
    const E_NOT_TOKEN: u64 = 4;

    #[resource_group_member(group = object::ObjectGroup)]
    struct Trading has key {
        transfer_ref: Option<TransferRef>, // none means disabled forever
        matching_collection: vector<String>, // empty means currently disabled
        matching_tokens: vector<String>, // empty means currently disabled
        match_all_tokens_in_collections: bool // still need collection names
    }

    public fun init_trading<T: key>(
        constructor_ref: &ConstructorRef,
        collection_name: String,
        token_name: String 
    ) {
        let obj = object::object_from_constructor_ref<T>(constructor_ref);
        assert!(
            token::collection(obj) == collection_name &&
            token::name(obj) == token_name,
            error::invalid_argument(E_NOT_TOKEN)
        );

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

    public fun freeze_trading<T: key>(owner: &signer, object: Object<T>)
    acquires Trading {
        clear_matching_names(owner, object);
        let trading = borrow_global_mut<Trading>(object::object_address(&object));
        _ = option::extract(&mut trading.transfer_ref);   
    }

    public fun add_matching_names<T: key>(
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

    public fun clear_matching_names<T: key>(owner: &signer, object: Object<T>)
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

    public fun set_matching_all_tokens_in_collections<T: key>(owner: &signer, object: Object<T>)
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

    public fun is_tradable_object<T: key>(object: Object<T>): bool
    acquires Trading {
        let obj_address = object::object_address(&object);
        if (exists<Trading>(obj_address)) {
            let trading = borrow_global<Trading>(obj_address);
            option::is_some(&trading.transfer_ref)
        } else {
            false
        }
    }

    public fun flash_offer<T1: key, T2: key>(
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

        assert!(is_tradable_object(object_to_offer), error::unavailable(E_TRADING_DISABLED));
        clear_matching_names(offerer, object_to_offer);

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

    #[test_only]
    use std::string::utf8;
    #[test_only]
    use aptos_token_objects::collection;

    #[test_only]
    struct FreePizzaPass has key {}

    #[test_only]
    struct FreeDonutPass has key {}

    #[test_only]
    fun setup_test(account_1: &signer, account_2: &signer)
    : (Object<FreePizzaPass>, Object<FreeDonutPass>) {
        _ = collection::create_untracked_collection(
            account_1,
            utf8(b"collection1 description"),
            utf8(b"collection1"),
            option::none(),
            utf8(b"collection1 uri"),
        );
        let cctor_1 = token::create(
            account_1,
            utf8(b"collection1"),
            utf8(b"description1"),
            utf8(b"name1"),
            option::none(),
            utf8(b"uri1")
        );
        move_to(&object::generate_signer(&cctor_1), FreePizzaPass{});
        init_trading<FreePizzaPass>(&cctor_1, utf8(b"collection1"), utf8(b"name1"));

        _ = collection::create_untracked_collection(
            account_2,
            utf8(b"collection2 description"),
            utf8(b"collection2"),
            option::none(),
            utf8(b"collection2 uri"),
        );
        let cctor_2 = token::create(
            account_2,
            utf8(b"collection2"),
            utf8(b"description2"),
            utf8(b"name2"),
            option::none(),
            utf8(b"uri2")
        );
        move_to(&object::generate_signer(&cctor_2), FreeDonutPass{});
        init_trading<FreeDonutPass>(&cctor_2, utf8(b"collection2"), utf8(b"name2"));

        let obj_1 = object::object_from_constructor_ref(&cctor_1);
        let obj_2 = object::object_from_constructor_ref(&cctor_2);
        (obj_1, obj_2)
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    fun test(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, obj_2) = setup_test(account_1, account_2);

        add_matching_names(
            account_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );

        assert!(object::is_owner(obj_1, @0x234), 0);
        assert!(object::is_owner(obj_2, @0x123), 1);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    fun test_2(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, obj_2) = setup_test(account_1, account_2);

        add_matching_names(
            account_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        set_matching_all_tokens_in_collections(account_1, obj_1);
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );

        assert!(object::is_owner(obj_1, @0x234), 0);
        assert!(object::is_owner(obj_2, @0x123), 1);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 65538, location = Self)]
    fun test_fail_empty(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, obj_2) = setup_test(account_1, account_2);

        add_matching_names(
            account_1,
            obj_1,
            vector<String>[],
            vector<String>[]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 65538, location = Self)]
    fun test_fail_empty_2(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, obj_2) = setup_test(account_1, account_2);

        add_matching_names(
            account_1,
            obj_1,
            vector<String>[],
            vector<String>[utf8(b"name2")]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 65538, location = Self)]
    fun test_fail_empty_3(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, obj_2) = setup_test(account_1, account_2);

        add_matching_names(
            account_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 851969, location = Self)]
    fun test_fail_freezed(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, obj_2) = setup_test(account_1, account_2);

        add_matching_names(
            account_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        freeze_trading(account_1, obj_1);
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 851969, location = Self)]
    fun test_fail_freezed_2(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, obj_2) = setup_test(account_1, account_2);

        add_matching_names(
            account_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        freeze_trading(account_2, obj_2);
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 65538, location = Self)]
    fun test_fail_trade_twice(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, obj_2) = setup_test(account_1, account_2);

        add_matching_names(
            account_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
        flash_offer(
            account_1,
            obj_2,
            obj_1
        );
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 65538, location = Self)]
    fun test_fail_trade_twice_2(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, obj_2) = setup_test(account_1, account_2);

        add_matching_names(
            account_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
        flash_offer(
            account_2,
            obj_1,
            obj_2
        );
    }
}