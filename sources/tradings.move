module tradable_token_objects::tradings {
    use std::signer;
    use std::vector;
    use std::error;
    use std::string::String;
    use std::option::{Self, Option};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_token_objects::token;
    use components_common::components_common::{Self, ComponentGroup, TransferKey};

    const E_TRADING_DISABLED: u64 = 1;
    const E_NOT_MATCHED: u64 = 2;
    const E_NOT_OWNER: u64 = 3;
    const E_NOT_TOKEN: u64 = 4;
    const E_NOT_STARTED: u64 = 5;
    const E_OWNER_CHANGED: u64 = 6;
    const E_OBJECT_REF_NOT_MATCH: u64 = 7;

    #[resource_group_member(group = ComponentGroup)]
    struct Trading has key {
        transfer_key: Option<TransferKey>,

        lister: Option<address>,
        matching_collection: vector<String>, // empty match none
        matching_tokens: vector<String>, // empty match none
        match_all_tokens_in_collections: bool // still need collection names
    }

    public fun init_trading<T: key>(
        extend_ref: &ExtendRef,
        object: Object<T>,
        collection_name: String,
        token_name: String 
    ) {
        assert!(
            token::collection(object) == collection_name &&
            token::name(object) == token_name,
            error::invalid_argument(E_NOT_TOKEN)
        );

        let obj_signer = object::generate_signer_for_extending(extend_ref);
        assert!(
            signer::address_of(&obj_signer) == object::object_address(&object),
            error::invalid_argument(E_OBJECT_REF_NOT_MATCH)
        );
        
        move_to(
            &obj_signer,
            Trading{
                transfer_key: option::none(),
                lister: option::none(),
                matching_collection: vector::empty(),
                matching_tokens: vector::empty(),
                match_all_tokens_in_collections: false
            }
        );
    }

    public fun start_trading<T: key>(
        owner: &signer,
        transfer_key: TransferKey,
        object: Object<T>,
        matching_collection_names: vector<String>,
        matching_token_names: vector<String>,
    )
    acquires Trading {
        assert!(
            object::is_owner(object, signer::address_of(owner)), 
            error::permission_denied(E_NOT_OWNER)
        );
        assert!(
            object::object_address(&object) == components_common::object_address(&transfer_key),
            error::invalid_argument(E_OBJECT_REF_NOT_MATCH)
        );
        let trading = borrow_global_mut<Trading>(object::object_address(&object));

        option::fill(&mut trading.lister, signer::address_of(owner));
        option::fill(&mut trading.transfer_key, transfer_key);
        trading.matching_collection = matching_collection_names;
        trading.matching_tokens = matching_token_names;
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
        assert!(option::is_some(&trading.lister), error::invalid_argument(E_NOT_STARTED));
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
        assert!(option::is_some(&trading.lister), error::invalid_argument(E_NOT_STARTED));
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
        assert!(option::is_some(&trading.lister), error::invalid_argument(E_NOT_STARTED));
        assert!(
            vector::length(&trading.matching_collection) > 0,
            error::invalid_argument(E_TRADING_DISABLED)
        );
        trading.matching_tokens = vector::empty();
        trading.match_all_tokens_in_collections = true;
    }

    public fun close<T: key>(owner: &signer, object: Object<T>)
    acquires Trading {
        assert!(
            object::is_owner(object, signer::address_of(owner)), 
            error::permission_denied(E_NOT_OWNER)
        );
        let trading = borrow_global_mut<Trading>(object::object_address(&object));
        trading.lister = option::none();
        trading.matching_collection = vector::empty();
        trading.matching_tokens = vector::empty();
        trading.match_all_tokens_in_collections = false;   
    }

    public fun freeze_trading<T: key>(owner: &signer, object: Object<T>): TransferKey
    acquires Trading {
        close(owner, object);
        let trading = borrow_global_mut<Trading>(object::object_address(&object));
        option::extract(&mut trading.transfer_key)   
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

        if (exists<Trading>(object::object_address(&object_to_offer))) {
            close(offerer, object_to_offer);
        };
        
        let target_trading = borrow_global_mut<Trading>(object::object_address(&target_object));
        let target_owner_address = object::owner(target_object);
        assert!(
            option::extract(&mut target_trading.lister) == target_owner_address,
            error::internal(E_OWNER_CHANGED)
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

        object::transfer(offerer, object_to_offer, target_owner_address);
        let linear_transfer = components_common::generate_linear_transfer_ref(option::borrow(&target_trading.transfer_key));
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
    : (Object<FreePizzaPass>, TransferKey, Object<FreeDonutPass>, TransferKey) {
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
        let ex_1 = object::generate_extend_ref(&cctor_1);
        let obj_1 = object::object_from_constructor_ref(&cctor_1);
        init_trading<FreePizzaPass>(&ex_1, obj_1, utf8(b"collection1"), utf8(b"name1"));

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
        let ex_2 = object::generate_extend_ref(&cctor_2);
        let obj_2 = object::object_from_constructor_ref(&cctor_2);
        init_trading<FreeDonutPass>(&ex_2, obj_2, utf8(b"collection2"), utf8(b"name2"));
        // wrong names
        // init_trading<FreeDonutPass>(&ex_2, obj_2, utf8(b"collection-bad"), utf8(b"name2"));
        // init_trading<FreeDonutPass>(&ex_2, obj_2, utf8(b"collection2"), utf8(b"name-bad"));

        (
            obj_1, components_common::create_transfer_key(&cctor_1), 
            obj_2, components_common::create_transfer_key(&cctor_2)
        )
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    fun test_matching_names(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, _, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );

        {
            let obj_1_addr = object::object_address(&obj_1);
            let trading_1 = borrow_global<Trading>(obj_1_addr);
            assert!(option::is_some(&trading_1.lister), 0);
            assert!(trading_1.matching_collection == vector<String>[utf8(b"collection2")], 1);
            assert!(trading_1.matching_tokens == vector<String>[utf8(b"name2")], 2);
            assert!(!trading_1.match_all_tokens_in_collections, 3);
            assert!(option::is_some(&trading_1.transfer_key), 4);
        };

        set_matching_all_tokens_in_collections(account_1, obj_1);
        {
            let obj_1_addr = object::object_address(&obj_1);
            let trading_1 = borrow_global<Trading>(obj_1_addr);
            assert!(trading_1.match_all_tokens_in_collections, 4);
        };

        add_matching_names(account_1, obj_1, vector<String>[utf8(b"collection3")], vector<String>[utf8(b"name3")]);
        {
            let obj_1_addr = object::object_address(&obj_1);
            let trading_1 = borrow_global<Trading>(obj_1_addr);
            assert!(option::is_some(&trading_1.lister), 0);
            assert!(trading_1.matching_collection == vector<String>[utf8(b"collection2"), utf8(b"collection3")], 1);
            assert!(trading_1.matching_tokens == vector<String>[utf8(b"name3")], 2);
            assert!(!trading_1.match_all_tokens_in_collections, 3);
            assert!(option::is_some(&trading_1.transfer_key), 4);
        };

        clear_matching_names(account_1, obj_1);
        {
            let obj_1_addr = object::object_address(&obj_1);
            let trading_1 = borrow_global<Trading>(obj_1_addr);
            assert!(option::is_some(&trading_1.lister), 3);
            assert!(vector::is_empty(&trading_1.matching_collection), 4);
            assert!(vector::is_empty(&trading_1.matching_tokens), 5);
            assert!(!trading_1.match_all_tokens_in_collections, 6);
        };

        close(account_1, obj_1);
        {
            let obj_1_addr = object::object_address(&obj_1);
            let trading_1 = borrow_global<Trading>(obj_1_addr);
            assert!(!option::is_some(&trading_1.lister), 3);
            assert!(option::is_some(&trading_1.transfer_key), 4);
        };

        let ret = freeze_trading(account_1, obj_1);
        {
            let obj_1_addr = object::object_address(&obj_1);
            let trading_1 = borrow_global<Trading>(obj_1_addr);
            assert!(option::is_none(&trading_1.transfer_key), 5);
        };

        components_common::destroy_for_test(key_2);
        components_common::destroy_for_test(ret);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    fun test(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
        let ret = freeze_trading(account_2, obj_1);

        assert!(object::is_owner(obj_1, @0x234), 0);
        assert!(object::is_owner(obj_2, @0x123), 1);

        {
            let trading_1 = borrow_global<Trading>(object::object_address(&obj_1));
            assert!(option::is_none(&trading_1.lister), 2);
            assert!(vector::is_empty(&trading_1.matching_collection), 3);
            assert!(vector::is_empty(&trading_1.matching_tokens), 4);
            assert!(!trading_1.match_all_tokens_in_collections, 5);
        };

        components_common::destroy_for_test(ret);
        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    fun test_any(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[]
        );
        set_matching_all_tokens_in_collections(account_1, obj_1);
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
        let ret = freeze_trading(account_2, obj_1);

        assert!(object::is_owner(obj_1, @0x234), 0);
        assert!(object::is_owner(obj_2, @0x123), 1);

        components_common::destroy_for_test(ret);
        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 65538, location = Self)]
    fun test_fail_matching_empty(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[],
            vector<String>[]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );

        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 65538, location = Self)]
    fun test_fail_matching_empty_2(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[],
            vector<String>[utf8(b"name2")]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );

        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 65538, location = Self)]
    fun test_fail_matching_empty_3(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );

        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure]
    fun test_fail_freezed(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        let key = freeze_trading(account_1, obj_1);
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );

        components_common::destroy_for_test(key);
        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure]
    fun test_fail_closed(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        close(account_1, obj_1);
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );

        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure]
    fun test_fail_trade_twice(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
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

        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure]
    fun test_fail_trade_twice_2(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
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

        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 327683, location = Self)]
    fun test_fail_wrong_claim(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
        let ret = freeze_trading(account_1, obj_1);

        components_common::destroy_for_test(ret);
        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    fun test_listing_both(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        start_trading(
            account_2,
            key_2,
            obj_2,
            vector<String>[utf8(b"collection1")],
            vector<String>[utf8(b"name1")]
        );

        flash_offer(
            account_2,
            obj_2,
            obj_1
        );

        {
            let trading_2 = borrow_global<Trading>(object::object_address(&obj_2));
            assert!(option::is_none(&trading_2.lister), 3);
            assert!(vector::is_empty(&trading_2.matching_collection), 4);
            assert!(vector::is_empty(&trading_2.matching_tokens), 5);
            assert!(!trading_2.match_all_tokens_in_collections, 6);
        };

        let ret_1 = freeze_trading(account_2, obj_1);
        let ret_2 = freeze_trading(account_1, obj_2);

        assert!(object::is_owner(obj_1, @0x234), 0);
        assert!(object::is_owner(obj_2, @0x123), 1);

        components_common::destroy_for_test(ret_1);
        components_common::destroy_for_test(ret_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure]
    fun test_fail_offer_self(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, _, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection1")],
            vector<String>[utf8(b"name1")]
        );

        flash_offer(
            account_1,
            obj_1,
            obj_1
        );

        let ret_1 = freeze_trading(account_1, obj_1);
        components_common::destroy_for_test(ret_1);
        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure]
    fun test_fail_offer_self_2(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, _, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection1")],
            vector<String>[]
        );
        set_matching_all_tokens_in_collections(account_1, obj_1);

        flash_offer(
            account_1,
            obj_1,
            obj_1
        );

        let ret_1 = freeze_trading(account_1, obj_1);
        components_common::destroy_for_test(ret_1);
        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 327683, location = Self)]
    fun test_fail_add_no_owner(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        add_matching_names(account_2, obj_1, vector<String>[utf8(b"collection3")], vector<String>[utf8(b"name2")]);
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
        let ret = freeze_trading(account_2, obj_1);
        components_common::destroy_for_test(ret);
        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 327683, location = Self)]
    fun test_fail_clear_no_owner(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        clear_matching_names(account_2, obj_1);
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
        let ret = freeze_trading(account_2, obj_1);
        components_common::destroy_for_test(ret);
        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 327683, location = Self)]
    fun test_fail_set_any_no_owner(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, obj_2, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        set_matching_all_tokens_in_collections(account_2, obj_1);
        flash_offer(
            account_2,
            obj_2,
            obj_1
        );
        let ret = freeze_trading(account_2, obj_1);
        components_common::destroy_for_test(ret);
        components_common::destroy_for_test(key_2);
    }

    #[test(account_1 = @0x123, account_2 = @0x234)]
    #[expected_failure(abort_code = 327683, location = Self)]
    fun test_fail_freeze_no_owner(account_1: &signer, account_2: &signer)
    acquires Trading {
        let (obj_1, key_1, _, key_2) = setup_test(account_1, account_2);

        start_trading(
            account_1,
            key_1,
            obj_1,
            vector<String>[utf8(b"collection2")],
            vector<String>[utf8(b"name2")]
        );
        let ret = freeze_trading(account_2, obj_1);
        components_common::destroy_for_test(ret);
        components_common::destroy_for_test(key_2);
    }
}