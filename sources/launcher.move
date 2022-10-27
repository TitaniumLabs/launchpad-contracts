/*

Account that controls this contract aka ADMIN (with only whitelisted addresses being able to call them)
Resource account that can control this contract where only account mentioned above can call it
Resource account created from this contract that allows users to interact with the contract, whilst being a sort of candy machine
 - CMV2 type resource account can create, delete, edit phases
 - CMV2 type resource account can change start timestamp, change end timestamp, force start, (supply, price, name, details immut)
 - CMV2 type resource account can add and remove accounts from phases
*/
module titanium_labs::launcher {
    // User not within whitelist members

    use std::string::{Self, String};
    use std::vector;
    use std::table::{Self, Table};
    use std::signer;
    use aptos_token::token;
    use aptos_framework::account;
    use aptos_std::table_with_length::{Self, TableWithLength};
    use aptos_framework::timestamp;
    use std::bcs;

    const SALT: vector<u8> = b"titanium_labs::launcher";

    const ECOLLECTION_ALREADY_EXISTS: u64 = 0;
    const EUSER_NOT_WHITELISTED: u64 = 1;
    const EMAX_QUANTITY_EXCEEDED: u64 = 2;
    const EMINT_EXCEEDS_MAXIMUM_SUPPLY: u64 = 3;
    const EPHASE_DOES_NOT_EXIST: u64 = 4;
    const EPHASE_ALREADY_STARTED: u64 = 5;
    const ECOLLECTION_NOT_CREATED: u64 = 6;

    // Dev only operations on this struct, stored in an account with only dev capabilities to call
    struct LaunchPadDetails has store, key {
        treasury_address: address,
        base_fee: u64,
    }


    struct DropDetails has store, key {
        collection_name: String,
        collection_details: String,
        base_uri: String,

        // Total supply including whitelist
        total_supply: u64,

        // Phases (can deploy multiple phases)
        phases: Table<String, Phase>,
        current_phase: String,

        // Track mints
        mints: TableWithLength<address, u64>,

        // Launch creator
        ra_signer_cap: account::SignerCapability,
    }



    struct Phase has store, key {
        name: String,
        price: u64,
        allocated_supply: u64,
        is_current: bool, // TODO: Maybe use this to force start before timestamp?
        start_timestamp: u64,
        end_timestamp: u64,
    }


    public fun create_drop(
        creator: &signer,
        collection_name: String,
        collection_details: String,
        total_supply: u64,
        base_uri: String, // https://cdn.titaniumlabs.app/metadata/<id>.json
        mutate_settings: vector<bool>,
        phases: vector<Phase>,
        start_phase_name: String,
    ) {
        let creator_addr = signer::address_of(creator);

        // Create seed consisting of module name, collection name and timestamp of creation
        let seed = bcs::to_bytes(&creator_addr);
        let curr_timestamp = bcs::to_bytes(&timestamp::now_microseconds());
        vector::append(&mut seed, SALT);
        vector::append(&mut seed, curr_timestamp);
        vector::append(&mut seed, *string::bytes(&collection_name));

        let (signer, signer_capabilities) = account::create_resource_account(creator, seed);

        // Create collection
        // TODO: Maybe handle mutation settings by default?
        token::create_collection(&signer, collection_name, collection_details, base_uri, total_supply, mutate_settings);


        let phases_table = table::new<String, Phase>();
        let starting_phase = table::borrow(&phases_table, start_phase_name);

        if (starting_phase.name == start_phase_name) {
            curr_phase.is_current = true;
        };

        let i = 0;
        while (i <= vector::length(&phases)) {
            let curr_phase = vector::borrow(&phases, i);
            table::add(&mut phases_table, curr_phase.name, *curr_phase);
            i = i + 1;
        };

        let mints = table_with_length::new<address, u64>();
        move_to(&signer, DropDetails{
            collection_name,
            collection_details,
            base_uri,
            total_supply,
            phases: phases_table,
            current_phase: start_phase_name,
            mints,
            ra_signer_cap: signer_capabilities,
        });

        assert!(exists<DropDetails>(signer::address_of(&signer)), ECOLLECTION_NOT_CREATED);
    }

    // Handle whitelist

    // Handle mint start

    // Handle mint
    public fun mint() {}
    public fun mint_whitelist() {}

    // Phase-related functionalities

    public fun delete_phase(creator: &signer, phase_name: String) acquires DropDetails {
        let creator_addr = signer::address_of(creator);
        let phases = borrow_global_mut<DropDetails>(creator_addr).phases;
        assert!(table::contains(&mut phases, *phase_name), EPHASE_DOES_NOT_EXIST);

        let phase_data = table::borrow_mut(&mut phases, *phase_name);
        assert!(timestamp::now_microseconds() > phase_data.start_timestamp, EPHASE_ALREADY_STARTED);

        table::remove(&mut phases, *phase_name);
    }

    public fun add_phase(
        creator: &signer,
        phase_name: String,
        price: u64,
        allocated_supply: u64,
        start_timestamp: u64,
        end_timestamp: u64,
    ) acquires DropDetails {
        let creator_addr = signer::address_of(creator);
        let phases = &mut borrow_global_mut<DropDetails>(creator_addr).phases;

        let new_phase = Phase {
            name: phase_name,
            price,
            allocated_supply,
            is_current: false,
            start_timestamp,
            end_timestamp,
        };

        table::add(phases, phase_name, new_phase);
    }

    public fun is_phase_over_allocated(creator: &signer, phase_name: String): bool acquires DropDetails {
        let creator_addr = signer::address_of(creator);
        let drop_details = borrow_global<DropDetails>(creator_addr);

        assert!(table::contains(&drop_details.phases, *phase_name), EPHASE_DOES_NOT_EXIST);

        let phase_data = table::borrow(&drop_details.phases, *phase_name);
        let total_minted = table_with_length::length(&drop_details.mints);

        let supply_left = drop_details.total_supply - total_minted;

        if (phase_data.allocated_supply >= supply_left) {
            true
        };

        false
    }

    // Admin functions

}
