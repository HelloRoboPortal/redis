######## HEXPIRE family commands
# Field does not exists
set E_NO_FIELD     -2
# Specified NX | XX | GT | LT condition not met
set E_FAIL         0
# expiration time set/updated
set E_OK           1
# Field deleted because the specified expiration time is in the past
set E_DELETED      2

######## HTTL family commands
set T_NO_FIELD    -2
set T_NO_EXPIRY   -1

######## HPERIST
set P_NO_FIELD    -2
set P_NO_EXPIRY   -1
set P_OK           1

######## HSETF
set S_FAIL          0
set S_FIELD         1
set S_FIELD_AND_TTL 3

############################### AUX FUNCS ######################################

proc create_hash {key entries} {
    r del $key
    foreach entry $entries {
        r hset $key [lindex $entry 0] [lindex $entry 1]
    }
}

proc get_keys {l} {
    set res {}
    foreach entry $l {
        set key [lindex $entry 0]
        lappend res $key
    }
    return $res
}

proc cmp_hrandfield_result {hash_name expected_result} {
    # Accumulate hrandfield results
    unset -nocomplain myhash
    array set myhash {}
    for {set i 0} {$i < 100} {incr i} {
        set key [r hrandfield $hash_name]
        set myhash($key) 1
    }
     set res [lsort [array names myhash]]
     if {$res eq $expected_result} {
        return 1
     } else {
        return $res
     }
}

proc hrandfieldTest {activeExpireConfig} {
    r debug set-active-expire $activeExpireConfig
    r del myhash
    set contents {{field1 1} {field2 2} }
    create_hash myhash $contents

    set factorValgrind [expr {$::valgrind ? 2 : 1}]

    # Set expiration time for field1 and field2 such that field1 expires first
    r hpexpire myhash 1 NX FIELDS 1 field1
    r hpexpire myhash 100 NX FIELDS 1 field2

    # On call hrandfield command lazy expire deletes field1 first
    wait_for_condition 8 10 {
        [cmp_hrandfield_result myhash "field2"] == 1
    } else {
        fail "Expected field2 to be returned by HRANDFIELD."
    }

    # On call hrandfield command lazy expire deletes field2 as well
    wait_for_condition 8 20 {
        [cmp_hrandfield_result myhash "{}"] == 1
    } else {
        fail "Expected {} to be returned by HRANDFIELD."
    }

    # restore the default value
    r debug set-active-expire 1
}

############################### TESTS #########################################

start_server {tags {"external:skip needs:debug"}} {
    foreach type {listpackex hashtable} {
        if {$type eq "hashtable"} {
            r config set hash-max-listpack-entries 0
        } else {
            r config set hash-max-listpack-entries 512
        }

        test "HPEXPIRE(AT) - Test 'NX' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hpexpire myhash 1000 NX FIELDS 1 field1] [list  $E_OK]
            assert_equal [r hpexpire myhash 1000 NX FIELDS 2 field1 field2] [list  $E_FAIL  $E_OK]

            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+1000)*1000}] NX FIELDS 1 field1] [list  $E_OK]
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+1000)*1000}] NX FIELDS 2 field1 field2] [list  $E_FAIL  $E_OK]
        }

        test "HPEXPIRE(AT) - Test 'XX' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hpexpire myhash 1000 NX FIELDS 2 field1 field2] [list  $E_OK  $E_OK]
            assert_equal [r hpexpire myhash 1000 XX FIELDS 2 field1 field3] [list  $E_OK  $E_FAIL]

            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+1000)*1000}] NX FIELDS 2 field1 field2] [list  $E_OK  $E_OK]
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+1000)*1000}] XX FIELDS 2 field1 field3] [list  $E_OK  $E_FAIL]
        }

        test "HPEXPIRE(AT) - Test 'GT' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2
            assert_equal [r hpexpire myhash 1000 NX FIELDS 1 field1] [list  $E_OK]
            assert_equal [r hpexpire myhash 2000 NX FIELDS 1 field2] [list  $E_OK]
            assert_equal [r hpexpire myhash 1500 GT FIELDS 2 field1 field2] [list  $E_OK  $E_FAIL]

            r del myhash
            r hset myhash field1 value1 field2 value2
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+1000)*1000}] NX FIELDS 1 field1] [list  $E_OK]
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+2000)*1000}] NX FIELDS 1 field2] [list  $E_OK]
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+1500)*1000}] GT FIELDS 2 field1 field2] [list  $E_OK  $E_FAIL]
        }

        test "HPEXPIRE(AT) - Test 'LT' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2
            assert_equal [r hpexpire myhash 1000 NX FIELDS 1 field1] [list  $E_OK]
            assert_equal [r hpexpire myhash 2000 NX FIELDS 1 field2] [list  $E_OK]
            assert_equal [r hpexpire myhash 1500 LT FIELDS 2 field1 field2] [list  $E_FAIL  $E_OK]

            r del myhash
            r hset myhash field1 value1 field2 value2
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+1000)*1000}] NX FIELDS 1 field1] [list  $E_OK]
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+2000)*1000}] NX FIELDS 1 field2] [list  $E_OK]
            assert_equal [r hpexpireat myhash [expr {([clock seconds]+1500)*1000}] LT FIELDS 2 field1 field2] [list  $E_FAIL  $E_OK]
        }

        test "HPEXPIREAT - field not exists or TTL is in the past ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2 f4 v4
            r hexpire myhash 1000 NX FIELDS 1 f4
            assert_equal [r hpexpireat myhash [expr {([clock seconds]-1)*1000}] NX FIELDS 4 f1 f2 f3 f4] "$E_DELETED $E_DELETED $E_NO_FIELD $E_FAIL"
            assert_equal [r hexists myhash field1] 0
        }

        test "HPEXPIRE - wrong number of arguments ($type)" {
            r del myhash
            r hset myhash f1 v1
            assert_error {*Parameter `numFields` should be greater than 0} {r hpexpire myhash 1000 NX FIELDS 0 f1 f2 f3}
            assert_error {*Parameter `numFileds` is more than number of arguments} {r hpexpire myhash 1000 NX FIELDS 4 f1 f2 f3}
        }

        test "HPEXPIRE - parameter expire-time near limit of  2^48 ($type)" {
            r del myhash
            r hset myhash f1 v1
            # below & above
            assert_equal [r hpexpire myhash [expr (1<<48) - [clock milliseconds] - 1000 ] FIELDS 1 f1] [list  $E_OK]
            assert_error {*invalid expire time*} {r hpexpire myhash [expr (1<<48) - [clock milliseconds] + 100 ] FIELDS 1 f1}
        }

        test "Lazy - doesn't delete hash that all its fields got expired ($type)" {
            r debug set-active-expire 0
            r flushall

            set hash_sizes {1 15 16 17 31 32 33 40}
            foreach h $hash_sizes {
                for {set i 1} {$i <= $h} {incr i} {
                    # random expiration time
                    r hset hrand$h f$i v$i
                    r hpexpire hrand$h [expr {50 + int(rand() * 50)}] FIELDS 1 f$i
                    assert_equal 1 [r HEXISTS hrand$h f$i]

                    # same expiration time
                    r hset same$h f$i v$i
                    r hpexpire same$h 100 FIELDS 1 f$i
                    assert_equal 1 [r HEXISTS same$h f$i]

                    # same expiration time
                    r hset mix$h f$i v$i fieldWithoutExpire$i v$i
                    r hpexpire mix$h 100 FIELDS 1 f$i
                    assert_equal 1 [r HEXISTS mix$h f$i]
                }
            }

            after 150

            # Verify that all fields got expired but keys wasn't lazy deleted
            foreach h $hash_sizes {
                for {set i 1} {$i <= $h} {incr i} {
                    assert_equal 0 [r HEXISTS mix$h f$i]
                }
                assert_equal 1 [r EXISTS hrand$h]
                assert_equal 1 [r EXISTS same$h]
                assert_equal [expr $h * 2] [r HLEN mix$h]
            }
            # Restore default
            r debug set-active-expire 1
        }

        test "Active - deletes hash that all its fields got expired ($type)" {
            r flushall

            set hash_sizes {1 15 16 17 31 32 33 40}
            foreach h $hash_sizes {
                for {set i 1} {$i <= $h} {incr i} {
                    # random expiration time
                    r hset hrand$h f$i v$i
                    r hpexpire hrand$h [expr {50 + int(rand() * 50)}] FIELDS 1 f$i
                    assert_equal 1 [r HEXISTS hrand$h f$i]

                    # same expiration time
                    r hset same$h f$i v$i
                    r hpexpire same$h 100 FIELDS 1 f$i
                    assert_equal 1 [r HEXISTS same$h f$i]

                    # same expiration time
                    r hset mix$h f$i v$i fieldWithoutExpire$i v$i
                    r hpexpire mix$h 100 FIELDS 1 f$i
                    assert_equal 1 [r HEXISTS mix$h f$i]
                }
            }

            # Wait for active expire
            wait_for_condition 50 20 { [r EXISTS same40] == 0 } else { fail "hash `same40` should be expired" }

            # Verify that all fields got expired and keys got deleted
            foreach h $hash_sizes {
                wait_for_condition 50 20 {
                    [r HLEN mix$h] == $h
                } else {
                    fail "volatile fields of hash `mix$h` should be expired"
                }

                for {set i 1} {$i <= $h} {incr i} {
                    assert_equal 0 [r HEXISTS mix$h f$i]
                }
                assert_equal 0 [r EXISTS hrand$h]
                assert_equal 0 [r EXISTS same$h]
            }
        }

        test "HPEXPIRE - Flushall deletes all pending expired fields ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2
            r hpexpire myhash 10000 NX FIELDS 1 field1
            r hpexpire myhash 10000 NX FIELDS 1 field2
            r flushall
            r del myhash
            r hset myhash field1 value1 field2 value2
            r hpexpire myhash 10000 NX FIELDS 1 field1
            r hpexpire myhash 10000 NX FIELDS 1 field2
            r flushall async
        }

        test "HTTL/HPTTL - Input validation gets failed on nonexists field or field without expire ($type)" {
            r del myhash
            r HSET myhash field1 value1 field2 value2
            r HPEXPIRE myhash 1000 NX FIELDS 1 field1

            foreach cmd {HTTL HPTTL} {
                assert_equal [r $cmd non_exists_key FIELDS 1 f] {}
                assert_equal [r $cmd myhash FIELDS 2 field2 non_exists_field] "$T_NO_EXPIRY $T_NO_FIELD"
                # Set numFields less than actual number of fields. Fine.
                assert_equal [r $cmd myhash FIELDS 1 non_exists_field1 non_exists_field2] "$T_NO_FIELD"
            }
        }

        test "HTTL/HPTTL - returns time to live in seconds/msillisec ($type)" {
            r del myhash
            r HSET myhash field1 value1 field2 value2
            r HPEXPIRE myhash 2000 NX FIELDS 2 field1 field2
            set ttlArray [r HTTL myhash FIELDS 2 field1 field2]
            assert_range [lindex $ttlArray 0] 1 2
            set ttl [r HPTTL myhash FIELDS 1 field1]
            assert_range $ttl 1000 2000
        }

        test "HEXPIRETIME - returns TTL in Unix timestamp ($type)" {
            r del myhash
            r HSET myhash field1 value1
            r HPEXPIRE myhash 1000 NX FIELDS 1 field1

            set lo [expr {[clock seconds] + 1}]
            set hi [expr {[clock seconds] + 2}]
            assert_range [r HEXPIRETIME myhash FIELDS 1 field1] $lo $hi
            assert_range [r HPEXPIRETIME myhash FIELDS 1 field1] [expr $lo*1000] [expr $hi*1000]
        }

        test "HTTL/HPTTL - Verify TTL progress until expiration ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2
            r hpexpire myhash 1000 NX FIELDS 1 field1
            assert_range [r HPTTL myhash FIELDS 1 field1] 100 1000
            assert_range [r HTTL myhash FIELDS 1 field1] 0 1
            after 100
            assert_range [r HPTTL myhash FIELDS 1 field1] 1 901
            after 910
            assert_equal [r HPTTL myhash FIELDS 1 field1] $T_NO_FIELD
            assert_equal [r HTTL myhash FIELDS 1 field1] $T_NO_FIELD
        }

        test "HPEXPIRE - DEL hash with non expired fields (valgrind test) ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2
            r hpexpire myhash 10000 NX FIELDS 1 field1
            r del myhash
        }

        test "HEXPIREAT - Set time in the past ($type)" {
            r del myhash
            r hset myhash field1 value1
            assert_equal [r hexpireat myhash [expr {[clock seconds] - 1}] NX FIELDS 1 field1] $E_DELETED
            assert_equal [r hexists myhash field1] 0
        }

        test "HEXPIREAT - Set time and then get TTL ($type)" {
            r del myhash
            r hset myhash field1 value1

            r hexpireat myhash [expr {[clock seconds] + 2}] NX FIELDS 1 field1
            assert_range [r hpttl myhash FIELDS 1 field1] 1000 2000
            assert_range [r httl myhash FIELDS 1 field1] 1 2

            r hexpireat myhash [expr {[clock seconds] + 5}] XX FIELDS 1 field1
            assert_range [r httl myhash FIELDS 1 field1] 4 5
        }

        test "Lazy expire - delete hash with expired fields ($type)" {
            r del myhash
            r debug set-active-expire 0
            r hset myhash k v
            r hpexpire myhash 1 NX FIELDS 1 k
            after 5
            r del myhash
            r debug set-active-expire 1
        }

        # OPEN: To decide if to delete expired fields at start of HRANDFIELD.
        #    test "Test HRANDFIELD does not return expired fields ($type)" {
        #        hrandfieldTest 0
        #        hrandfieldTest 1
        #    }

        test "Test HRANDFIELD can return expired fields ($type)" {
            r debug set-active-expire 0
            r del myhash
            r hset myhash f1 v1 f2 v2 f3 v3 f4 v4 f5 v5
            r hpexpire myhash 1 NX FIELDS 4 f1 f2 f3 f4
            after 5
            set res [cmp_hrandfield_result myhash "f1 f2 f3 f4 f5"]
            assert {$res == 1}
            r debug set-active-expire 1

        }

        test "Lazy expire - HLEN does count expired fields ($type)" {
            # Enforce only lazy expire
            r debug set-active-expire 0

            r del h1 h4 h18 h20
            r hset h1 k1 v1
            r hpexpire h1 1 NX FIELDS 1 k1

            r hset h4 k1 v1 k2 v2 k3 v3 k4 v4
            r hpexpire h4 1 NX FIELDS 3 k1 k3 k4

            # beyond 16 fields: HFE DS (ebuckets) converts from list to rax

            r hset h18 k1 v1 k2 v2 k3 v3 k4 v4 k5 v5 k6 v6 k7 v7 k8 v8 k9 v9 k10 v10 k11 v11 k12 v12 k13 v13 k14 v14 k15 v15 k16 v16 k17 v17 k18 v18
            r hpexpire h18 1 NX FIELDS 18 k1 k2 k3 k4 k5 k6 k7 k8 k9 k10 k11 k12 k13 k14 k15 k16 k17 k18

            r hset h20 k1 v1 k2 v2 k3 v3 k4 v4 k5 v5 k6 v6 k7 v7 k8 v8 k9 v9 k10 v10 k11 v11 k12 v12 k13 v13 k14 v14 k15 v15 k16 v16 k17 v17 k18 v18 k19 v19 k20 v20
            r hpexpire h20 1 NX FIELDS 2 k1 k2

            after 10

            assert_equal [r hlen h1] 1
            assert_equal [r hlen h4] 4
            assert_equal [r hlen h18] 18
            assert_equal [r hlen h20] 20
            # Restore to support active expire
            r debug set-active-expire 1
        }

        test "Lazy expire - HSCAN does not report expired fields ($type)" {
            # Enforce only lazy expire
            r debug set-active-expire 0

            r del h1 h20 h4 h18 h20
            r hset h1 01 01
            r hpexpire h1 1 NX FIELDS 1 01

            r hset h4 01 01 02 02 03 03 04 04
            r hpexpire h4 1 NX FIELDS 3 01 03 04

            # beyond 16 fields hash-field expiration DS (ebuckets) converts from list to rax

            r hset h18 01 01 02 02 03 03 04 04 05 05 06 06 07 07 08 08 09 09 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18
            r hpexpire h18 1 NX FIELDS 18 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18

            r hset h20 01 01 02 02 03 03 04 04 05 05 06 06 07 07 08 08 09 09 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20
            r hpexpire h20 1 NX FIELDS 2 01 02

            after 10

            # Verify SCAN does not report expired fields
            assert_equal [lsort -unique [lindex [r hscan h1 0 COUNT 10] 1]] ""
            assert_equal [lsort -unique [lindex [r hscan h4 0 COUNT 10] 1]] "02"
            assert_equal [lsort -unique [lindex [r hscan h18 0 COUNT 10] 1]] ""
            assert_equal [lsort -unique [lindex [r hscan h20 0 COUNT 100] 1]] "03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20"
            # Restore to support active expire
            r debug set-active-expire 1
        }

        test "Test HSCAN with mostly expired fields return empty result ($type)" {
            r debug set-active-expire 0

            # Create hash with 1000 fields and 999 of them will be expired
            r del myhash
            for {set i 1} {$i <= 1000} {incr i} {
                r hset myhash field$i value$i
                if {$i > 1} {
                    r hpexpire myhash 1 NX FIELDS 1 field$i
                }
            }
            after 3

            # Verify iterative HSCAN returns either empty result or only the first field
            set countEmptyResult 0
            set cur 0
            while 1 {
                set res [r hscan myhash $cur]
                set cur [lindex $res 0]
                # if the result is not empty, it should contain only the first field
                if {[llength [lindex $res 1]] > 0} {
                    assert_equal [lindex $res 1] "field1 value1"
                } else {
                    incr countEmptyResult
                }
                if {$cur == 0} break
            }
            assert {$countEmptyResult > 0}
            r debug set-active-expire 1
        }

        test "Lazy expire - verify various HASH commands handling expired fields ($type)" {
            # Enforce only lazy expire
            r debug set-active-expire 0
            r del h1 h2 h3 h4 h5 h18
            r hset h1 01 01
            r hset h2 01 01 02 02
            r hset h3 01 01 02 02 03 03
            r hset h4 1 99 2 99 3 99 4 99
            r hset h5 1 1 2 22 3 333 4 4444 5 55555
            r hset h6 01 01 02 02 03 03 04 04 05 05 06 06
            r hset h18 01 01 02 02 03 03 04 04 05 05 06 06 07 07 08 08 09 09 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18
            r hpexpire h1 100 NX FIELDS 1 01
            r hpexpire h2 100 NX FIELDS 1 01
            r hpexpire h2 100 NX FIELDS 1 02
            r hpexpire h3 100 NX FIELDS 1 01
            r hpexpire h4 100 NX FIELDS 1 2
            r hpexpire h5 100 NX FIELDS 1 3
            r hpexpire h6 100 NX FIELDS 1 05
            r hpexpire h18 100 NX FIELDS 17 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17

            after 150

            # Verify HDEL not ignore expired field. It is too much overhead to check
            # if the field is expired before deletion.
            assert_equal [r HDEL h1 01] "1"

            # Verify HGET ignore expired field
            assert_equal [r HGET h2 01] ""
            assert_equal [r HGET h2 02] ""
            assert_equal [r HGET h3 01] ""
            assert_equal [r HGET h3 02] "02"
            assert_equal [r HGET h3 03] "03"
            # Verify HINCRBY ignore expired field
            assert_equal [r HINCRBY h4 2 1] "1"
            assert_equal [r HINCRBY h4 3 1] "100"
            # Verify HSTRLEN ignore expired field
            assert_equal [r HSTRLEN h5 3] "0"
            assert_equal [r HSTRLEN h5 4] "4"
            assert_equal [lsort [r HKEYS h6]] "01 02 03 04 06"
            # Verify HEXISTS ignore expired field
            assert_equal [r HEXISTS h18 07] "0"
            assert_equal [r HEXISTS h18 18] "1"
            # Verify HVALS ignore expired field
            assert_equal [lsort [r HVALS h18]] "18"
            # Restore to support active expire
            r debug set-active-expire 1
        }

        test "A field with TTL overridden with another value (TTL discarded) ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            r hpexpire myhash 10000 NX FIELDS 1 field1
            r hpexpire myhash 1 NX FIELDS 1 field2

            # field2 TTL will be discarded
            r hset myhash field2 value4
            after 5
            # Expected TTL will be discarded
            assert_equal [r hget myhash field2] "value4"
            assert_equal [r httl myhash FIELDS 2 field2 field3] "$T_NO_EXPIRY $T_NO_EXPIRY"
            assert_not_equal [r httl myhash FIELDS 1 field1] "$T_NO_EXPIRY"
        }

        test "Modify TTL of a field ($type)" {
            r del myhash
            r hset myhash field1 value1
            r hpexpire myhash 200000 NX FIELDS 1 field1
            r hpexpire myhash 1000000 XX FIELDS 1 field1
            after 15
            assert_equal [r hget myhash field1] "value1"
            assert_range [r hpttl myhash FIELDS 1 field1] 900000 1000000
        }

        test "Test return value of set operation ($type)" {
             r del myhash
             r hset myhash f1 v1 f2 v2
             r hexpire myhash 100000 FIELDS 1 f1
             assert_equal [r hset myhash f2 v2] 0
             assert_equal [r hset myhash f3 v3] 1
             assert_equal [r hset myhash f3 v3 f4 v4] 1
             assert_equal [r hset myhash f3 v3 f5 v5 f6 v6] 2
        }

        test "Test HGETALL not return expired fields ($type)" {
            # Test with small hash
            r debug set-active-expire 0
            r del myhash
            r hset myhash1 f1 v1 f2 v2 f3 v3 f4 v4 f5 v5 f6 v6
            r hpexpire myhash1 1 NX FIELDS 3 f2 f4 f6
            after 10
            assert_equal [lsort [r hgetall myhash1]] "f1 f3 f5 v1 v3 v5"

            # Test with large hash
            r del myhash
            for {set i 1} {$i <= 600} {incr i} {
                r hset myhash f$i v$i
                if {$i > 3} { r hpexpire myhash 1 NX FIELDS 1 f$i }
            }
            after 10
            assert_equal [lsort [r hgetall myhash]] [lsort "f1 f2 f3 v1 v2 v3"]
            r debug set-active-expire 1
        }

        test "Test RENAME hash with fields to be expired ($type)" {
            r debug set-active-expire 0
            r del myhash
            r hset myhash field1 value1
            r hpexpire myhash 20 NX FIELDS 1 field1
            r rename myhash myhash2
            assert_equal [r exists myhash] 0
            assert_range [r hpttl myhash2 FIELDS 1 field1] 1 20
            after 25
            # Verify the renamed key exists
            assert_equal [r exists myhash2] 1
            r debug set-active-expire 1
            # Only active expire will delete the key
            wait_for_condition 30 10 { [r exists myhash2] == 0 } else { fail "`myhash2` should be expired" }
        }

        test "MOVE to another DB hash with fields to be expired ($type)" {
            r select 9
            r flushall
            r hset myhash field1 value1
            r hpexpire myhash 100 NX FIELDS 1 field1
            r move myhash 10
            assert_equal [r exists myhash] 0
            assert_equal [r dbsize] 0

            # Verify the key and its field exists in the target DB
            r select 10
            assert_equal [r hget myhash field1] "value1"
            assert_equal [r exists myhash] 1

            # Eventually the field will be expired and the key will be deleted
            wait_for_condition 40 10 { [r hget myhash field1] == "" } else { fail "`field1` should be expired" }
            wait_for_condition 40 10 { [r exists myhash] == 0 } else { fail "db should be empty" }
        } {} {singledb:skip}

        test "Test COPY hash with fields to be expired ($type)" {
            r flushall
            r hset h1 f1 v1 f2 v2
            r hset h2 f1 v1 f2 v2 f3 v3 f4 v4 f5 v5 f6 v6 f7 v7 f8 v8 f9 v9 f10 v10 f11 v11 f12 v12 f13 v13 f14 v14 f15 v15 f16 v16 f17 v17 f18 v18
            r hpexpire h1 100 NX FIELDS 1 f1
            r hpexpire h2 100 NX FIELDS 18 f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 f13 f14 f15 f16 f17 f18
            r COPY h1 h1copy
            r COPY h2 h2copy
            assert_equal [r hget h1 f1] "v1"
            assert_equal [r hget h1copy f1] "v1"
            assert_equal [r exists h2] 1
            assert_equal [r exists h2copy] 1
            after 105

            # Verify lazy expire of field in h1 and its copy
            assert_equal [r hget h1 f1] ""
            assert_equal [r hget h1copy f1] ""

            # Verify lazy expire of field in h2 and its copy. Verify the key deleted as well.
            wait_for_condition 40 10 { [r exists h2] == 0 } else { fail "`h2` should be expired" }
            wait_for_condition 40 10 { [r exists h2copy] == 0 } else { fail "`h2copy` should be expired" }

        } {} {singledb:skip}

        test "Test SWAPDB hash-fields to be expired ($type)" {
            r select 9
            r flushall
            r hset myhash field1 value1
            r hpexpire myhash 50 NX FIELDS 1 field1

            r swapdb 9 10

            # Verify the key and its field doesn't exist in the source DB
            assert_equal [r exists myhash] 0
            assert_equal [r dbsize] 0

            # Verify the key and its field exists in the target DB
            r select 10
            assert_equal [r hget myhash field1] "value1"
            assert_equal [r dbsize] 1

            # Eventually the field will be expired and the key will be deleted
            wait_for_condition 20 10 { [r exists myhash] == 0 } else { fail "'myhash' should be expired" }
        } {} {singledb:skip}

        test "HPERSIST - input validation ($type)" {
            # HPERSIST key <num-fields> <field [field ...]>
            r del myhash
            r hset myhash f1 v1 f2 v2
            r hexpire myhash 1000 NX FIELDS 1 f1
            assert_error {*wrong number of arguments*} {r hpersist myhash}
            assert_error {*wrong number of arguments*} {r hpersist myhash FIELDS 1}
            assert_equal [r hpersist not-exists-key FIELDS 1 f1] {}
            assert_equal [r hpersist myhash FIELDS 2 f1 not-exists-field] "$P_OK $P_NO_FIELD"
            assert_equal [r hpersist myhash FIELDS 1 f2] "$P_NO_EXPIRY"
        }

        test "HPERSIST - verify fields with TTL are persisted ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2
            r hexpire myhash 20 NX FIELDS 2 f1 f2
            r hpersist myhash FIELDS 2 f1 f2
            after 25
            assert_equal [r hget myhash f1] "v1"
            assert_equal [r hget myhash f2] "v2"
            assert_equal [r HTTL myhash FIELDS 2 f1 f2] "$T_NO_EXPIRY $T_NO_EXPIRY"
        }

        test "HTTL/HPERSIST - Test expiry commands with non-volatile hash ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r httl myhash FIELDS 1 field1] $T_NO_EXPIRY
            assert_equal [r httl myhash FIELDS 1 fieldnonexist] $E_NO_FIELD

            assert_equal [r hpersist myhash FIELDS 1 field1] $P_NO_EXPIRY
            assert_equal [r hpersist myhash FIELDS 1 fieldnonexist] $P_NO_FIELD
        }

        test "HGETF - input validation ($type)" {
            assert_error {*wrong number of arguments*} {r hgetf myhash}
            assert_error {*wrong number of arguments*} {r hgetf myhash fields}
            assert_error {*wrong number of arguments*} {r hgetf myhash fields 1}
            assert_error {*wrong number of arguments*} {r hgetf myhash fields 2 a}
            assert_error {*wrong number of arguments*} {r hgetf myhash fields 3 a b}
            assert_error {*wrong number of arguments*} {r hgetf myhash fields 3 a b}
            assert_error {*unknown argument*} {r hgetf myhash fields 1 a unknown}
            assert_error {*missing FIELDS argument*} {r hgetf myhash nx ex 100}
            assert_error {*multiple FIELDS argument*} {r hgetf myhash fields 1 a fields 1 b}

            r hset myhash f1 v1 f2 v2 f3 v3
            # NX, XX, GT, and LT can be specified only when EX, PX, EXAT, or PXAT is specified
            assert_error {*only when EX, PX, EXAT, or PXAT is specified*} {r hgetf myhash nx fields 1 a}
            assert_error {*only when EX, PX, EXAT, or PXAT is specified*} {r hgetf myhash xx fields 1 a}
            assert_error {*only when EX, PX, EXAT, or PXAT is specified*} {r hgetf myhash gt fields 1 a}
            assert_error {*only when EX, PX, EXAT, or PXAT is specified*} {r hgetf myhash lt fields 1 a}

            # Only one of NX, XX, GT, and LT can be specified
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hgetf myhash nx xx EX 100 fields 1 a}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hgetf myhash xx nx EX 100 fields 1 a}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hgetf myhash gt nx EX 100 fields 1 a}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hgetf myhash gt lt EX 100 fields 1 a}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hgetf myhash xx gt EX 100 fields 1 a}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hgetf myhash lt gt EX 100 fields 1 a}

            # Only one of EX, PX, EXAT, PXAT or PERSIST can be specified
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash EX 100 PX 1000 fields 1 a}
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash EX 100 EXAT 100 fields 1 a}
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash EXAT 100 EX 1000 fields 1 a}
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash EXAT 100 PX 1000 fields 1 a}
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash PX 100 EXAT 100 fields 1 a}
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash PX 100 PXAT 100 fields 1 a}
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash PXAT 100 EX 100 fields 1 a}
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash PXAT 100 EXAT 100 fields 1 a}
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash EX 100 PERSIST fields 1 a}
            assert_error {*Only one of EX, PX, EXAT, PXAT or PERSIST arguments*} {r hgetf myhash PERSIST EX 100 fields 1 a}

            # missing expire time
            assert_error {*not an integer or out of range*} {r hgetf myhash ex fields 1 a}
            assert_error {*not an integer or out of range*} {r hgetf myhash px fields 1 a}
            assert_error {*not an integer or out of range*} {r hgetf myhash exat fields 1 a}
            assert_error {*not an integer or out of range*} {r hgetf myhash pxat fields 1 a}

            # expire time more than 2 ^ 48
            assert_error {*invalid expire time*} {r hgetf myhash EXAT [expr (1<<48)] 1 f1}
            assert_error {*invalid expire time*} {r hgetf myhash PXAT [expr (1<<48)] 1 f1}
            assert_error {*invalid expire time*} {r hgetf myhash EX [expr (1<<48) - [clock seconds] + 1000 ] 1 f1}
            assert_error {*invalid expire time*} {r hgetf myhash PX [expr (1<<48) - [clock milliseconds] + 1000 ] 1 f1}

            # negative expire time
            assert_error {*invalid expire time*} {r hgetf myhash EXAT -10 1 f1}

            # negative field value count
            assert_error {*invalid number of fields*} {r hgetf myhash fields -1 a}
        }

        test "HGETF - Verify field value reply type is string ($type)" {
            r del myhash
            r hsetf myhash FVS 1 f1 1

            r readraw 1
            assert_equal [r hgetf myhash FIELDS 1 f1] {*1}
            assert_equal [r read] {$1}
            assert_equal [r read] {1}
            r readraw 0
        }

        test "HGETF - Test 'NX' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hgetf myhash EX 1000 NX FIELDS 1 field1] [list  "value1"]
            assert_equal [r hgetf myhash EX 10000 NX FIELDS 2 field1 field2] [list  "value1" "value2"]
            assert_range [r httl myhash FIELDS 1 field1] 1 1000
            assert_range [r httl myhash FIELDS 1 field2] 5000 10000

            # A field with no expiration is treated as an infinite expiration.
            # LT should set the expire time if field has no TTL.
            r del myhash
            r hset myhash field1 value1
            assert_equal [r hgetf myhash EX 1500 LT FIELDS 1 field1]  [list  "value1"]
            assert_not_equal [r httl myhash FIELDS 1 field1] "$T_NO_EXPIRY"
        }

        test "HGETF - Test 'XX' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hgetf myhash EX 1000 NX FIELDS 1 field1] [list  "value1"]
            assert_equal [r hgetf myhash EX 10000 XX FIELDS 2 field1 field2] [list  "value1" "value2"]
            assert_range [r httl myhash FIELDS 1 field1] 9900 10000
            assert_equal [r httl myhash FIELDS 1 field2] "$T_NO_EXPIRY"
        }

        test "HGETF - Test 'GT' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hgetf myhash EX 1000 NX FIELDS 1 field1] [list  "value1"]
            assert_equal [r hgetf myhash EX 2000 NX FIELDS 1 field2] [list  "value2"]
            assert_equal [r hgetf myhash EX 1500 GT FIELDS 2 field1 field2] [list  "value1" "value2"]
            assert_range [r httl myhash FIELDS 1 field1] 1400 1500
            assert_range [r httl myhash FIELDS 1 field2] 1900 2000
        }

        test "HGETF - Test 'LT' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hgetf myhash EX 1000 NX FIELDS 1 field1] [list  "value1"]
            assert_equal [r hgetf myhash EX 2000 NX FIELDS 1 field2] [list  "value2"]
            assert_equal [r hgetf myhash EX 1500 LT FIELDS 2 field1 field2] [list  "value1" "value2"]
            assert_range [r httl myhash FIELDS 1 field1] 1 1000
            assert_range [r httl myhash FIELDS 1 field2] 1000 1500
        }

        test "HGETF - Test 'EX' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hgetf myhash EX 1000 FIELDS 1 field3] [list "value3"]
            assert_range [r httl myhash FIELDS 1 field3] 1 1000
        }

        test "HGETF - Test 'EXAT' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hgetf myhash EXAT 4000000000 FIELDS 1 field3] [list "value3"]
            assert_range [expr [r httl myhash FIELDS 1 field3] + [clock seconds]] 3900000000 4000000000
        }

        test "HGETF - Test 'PX' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hgetf myhash PX 1000000 FIELDS 1 field3] [list "value3"]
            assert_range [r httl myhash FIELDS 1 field3] 900 1000
        }

        test "HGETF - Test 'PXAT' flag ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            assert_equal [r hgetf myhash PXAT 4000000000000 FIELDS 1 field3] [list "value3"]
            assert_range [expr [r httl myhash FIELDS 1 field3] + [clock seconds]] 3900000000 4000000000
        }

        test "HGETF - Test 'PERSIST' flag ($type)" {
            r del myhash
            r debug set-active-expire 0

            r hset myhash f1 v1 f2 v2 f3 v3
            r hgetf myhash PX 5000 FIELDS 3 f1 f2 f3
            assert_not_equal [r httl myhash FIELDS 1 f1] "$T_NO_EXPIRY"
            assert_not_equal [r httl myhash FIELDS 1 f2] "$T_NO_EXPIRY"
            assert_not_equal [r httl myhash FIELDS 1 f3] "$T_NO_EXPIRY"

            assert_equal [r hgetf myhash PERSIST FIELDS 1 f1] "v1"
            assert_equal [r httl myhash FIELDS 1 f1]  "$T_NO_EXPIRY"

            assert_equal [r hgetf myhash PERSIST FIELDS 2 f2 f3] "v2 v3"
            assert_equal [r httl myhash FIELDS 2 f2 f3]  "$T_NO_EXPIRY $T_NO_EXPIRY"
        }

        test "HGETF - Test setting expired ttl deletes key ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2 f3 v3

            # hgetf without setting ttl
            assert_equal [lsort [r hgetf myhash fields 3 f1 f2 f3]] [lsort "v1 v2 v3"]
            assert_equal [r httl myhash FIELDS 3 f1 f2 f3] "$T_NO_EXPIRY $T_NO_EXPIRY $T_NO_EXPIRY"

            # set expired ttl and verify key is deleted
            r hgetf myhash PXAT 1 fields 3 f1 f2 f3
            assert_equal [r exists myhash] 0
        }

        test "HGETF - Test active expiry ($type)" {
            r del myhash
            r debug set-active-expire 0

            r hset myhash f1 v1 f2 v2 f3 v3 f4 v4 f5 v5
            r hgetf myhash PXAT 1 FIELDS 5 f1 f2 f3 f4 f5

            r debug set-active-expire 1
            wait_for_condition 50 20 { [r EXISTS myhash] == 0 } else { fail "'myhash' should be expired" }
        }

        test "HGETF - A field with TTL overridden with another value (TTL discarded) ($type)" {
            r del myhash
            r hset myhash field1 value1 field2 value2 field3 value3
            r hgetf myhash PX 10000 NX FIELDS 1 field1
            r hgetf myhash EX 100 NX FIELDS 1 field2

            # field2 TTL will be discarded
            r hset myhash field2 value4

            # Expected TTL will be discarded
            assert_equal [r hget myhash field2] "value4"
            assert_equal [r httl myhash FIELDS 2 field2 field3] "$T_NO_EXPIRY $T_NO_EXPIRY"

            # Other field is not affected.
            assert_not_equal [r httl myhash FIELDS 1 field1] "$T_NO_EXPIRY"
        }

        test "HSETF - input validation ($type)" {
            assert_error {*wrong number of arguments*} {r hsetf myhash}
            assert_error {*wrong number of arguments*} {r hsetf myhash fvs}
            assert_error {*wrong number of arguments*} {r hsetf myhash fvs 1}
            assert_error {*wrong number of arguments*} {r hsetf myhash fvs 2 a b}
            assert_error {*wrong number of arguments*} {r hsetf myhash fvs 3 a b c d}
            assert_error {*wrong number of arguments*} {r hsetf myhash fvs 3 a b}
            assert_error {*unknown argument*} {r hsetf myhash fvs 1 a b unknown}
            assert_error {*missing FVS argument*} {r hsetf myhash nx nx ex 100}
            assert_error {*multiple FVS argument*} {r hsetf myhash DC fvs 1 a b fvs 1 a b}

            r hset myhash f1 v1 f2 v2 f3 v3
            # NX, XX, GT, and LT can be specified only when EX, PX, EXAT, or PXAT is specified
            assert_error {*only when EX, PX, EXAT, or PXAT is specified*} {r hsetf myhash nx fvs 1 a b}
            assert_error {*only when EX, PX, EXAT, or PXAT is specified*} {r hsetf myhash xx fvs 1 a b}
            assert_error {*only when EX, PX, EXAT, or PXAT is specified*} {r hsetf myhash gt fvs 1 a b}
            assert_error {*only when EX, PX, EXAT, or PXAT is specified*} {r hsetf myhash lt fvs 1 a b}

            # Only one of NX, XX, GT, and LT can be specified
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hsetf myhash nx xx EX 100 fvs 1 a b}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hsetf myhash xx nx EX 100 fvs 1 a b}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hsetf myhash gt nx EX 100 fvs 1 a b}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hsetf myhash gt lt EX 100 fvs 1 a b}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hsetf myhash xx gt EX 100 fvs 1 a b}
            assert_error {*Only one of NX, XX, GT, and LT arguments*} {r hsetf myhash lt gt EX 100 fvs 1 a b}

            # Only one of EX, PX, EXAT, PXAT or KEEPTTL can be specified
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash EX 100 PX 1000 fvs 1 a b}
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash EX 100 EXAT 100 fvs 1 a b}
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash EXAT 100 EX 1000 fvs 1 a b}
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash EXAT 100 PX 1000 fvs 1 a b}
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash PX 100 EXAT 100 fvs 1 a b}
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash PX 100 PXAT 100 fvs 1 a b}
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash PXAT 100 EX 100 fvs 1 a b}
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash PXAT 100 EXAT 100 fvs 1 a b}
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash EX 100 KEEPTTL fvs 1 a b}
            assert_error {*Only one of EX, PX, EXAT, PXAT or KEEPTTL arguments*} {r hsetf myhash KEEPTTL EX 100 fvs 1 a b}

            # Only one of DCF, DOF can be specified
            assert_error {*Only one of DCF or DOF arguments can be specified*} {r hsetf myhash DCF DOF fvs 1 a b}
            assert_error {*Only one of DCF or DOF arguments can be specified*} {r hsetf myhash DOF DCF fvs 1 a b}

            # Only one of GETNEW, GETOLD can be specified
            assert_error {*Only one of GETOLD or GETNEW arguments can be specified*} {r hsetf myhash GETNEW GETOLD fvs 1 a b}
            assert_error {*Only one of GETOLD or GETNEW arguments can be specified*} {r hsetf myhash GETOLD GETNEW fvs 1 a b}

            # missing expire time
            assert_error {*not an integer or out of range*} {r hsetf myhash ex fvs 1 a b}
            assert_error {*not an integer or out of range*} {r hsetf myhash px fvs 1 a b}
            assert_error {*not an integer or out of range*} {r hsetf myhash exat fvs 1 a b}
            assert_error {*not an integer or out of range*} {r hsetf myhash pxat fvs 1 a b}

            # expire time more than 2 ^ 48
            assert_error {*invalid expire time*} {r hsetf myhash EXAT [expr (1<<48)] 1 a b}
            assert_error {*invalid expire time*} {r hsetf myhash PXAT [expr (1<<48)] 1 a b}
            assert_error {*invalid expire time*} {r hsetf myhash EX [expr (1<<48) - [clock seconds] + 1000 ] 1 a b}
            assert_error {*invalid expire time*} {r hsetf myhash PX [expr (1<<48) - [clock milliseconds] + 1000 ] 1 a b}

            # negative ttl
            assert_error {*invalid expire time*} {r hsetf myhash EXAT -1 1 a b}

            # negative field value count
            assert_error {*invalid number of fvs count*} {r hsetf myhash fvs -1 a b}
        }

        test "HSETF - Verify field value reply type is string ($type)" {
            r del myhash
            r hsetf myhash FVS 1 field 1
            r readraw 1

            # Test with GETOLD
            assert_equal [r hsetf myhash GETOLD FVS 1 field 200] {*1}
            assert_equal [r read] {$1}
            assert_equal [r read] {1}

            # Test with GETNEW.
            assert_equal [r hsetf myhash DOF GETNEW FVS 1 field 300] {*1}
            assert_equal [r read] {$3}
            assert_equal [r read] {200}

            r readraw 0
        }

        test "HSETF - Test DC flag ($type)" {
            r del myhash
            # don't create key
            assert_equal "" [r hsetf myhash DC fvs 1 a b]
        }

        test "HSETF - Test DCF/DOF flag ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2 f3 v3

            # Don't overwrite fields
            assert_equal [r hsetf myhash DOF fvs 2 f1 n1 f2 n2] "$S_FAIL $S_FAIL"
            assert_equal [r hsetf myhash DOF fvs 3 f1 n1 f2 b2 f4 v4] "$S_FAIL $S_FAIL $S_FIELD"
            assert_equal [lsort [r hgetall myhash]] [lsort "f1 v1 f2 v2 f3 v3 f4 v4"]

            # Don't create fields
            assert_equal [r hsetf myhash DCF fvs 3 f1 n1 f2 b2 f5 v5] "$S_FIELD $S_FIELD $S_FAIL"
            assert_equal [lsort [r hgetall myhash]] [lsort "f1 n1 f2 b2 f3 v3 f4 v4"]
        }

        test "HSETF - Test 'NX' flag ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2 f3 v3
            assert_equal [r hsetf myhash EX 1000 NX FVS 1 f1 n1] "$S_FIELD_AND_TTL"
            assert_equal [r hsetf myhash EX 10000 NX FVS 2 f1 n1 f2 n2] "$S_FIELD $S_FIELD_AND_TTL"
            assert_range [r httl myhash FIELDS 1 f1] 990 1000
            assert_range [r httl myhash FIELDS 1 f2] 9990 10000
        }

        test "HSETF - Test 'XX' flag ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2 f3 v3
            assert_equal [r hsetf myhash EX 1000 NX FVS 1 f1 n1] "$S_FIELD_AND_TTL"
            assert_equal [r hsetf myhash EX 10000 XX FVS 2 f1 n1 f2 n2] "$S_FIELD_AND_TTL $S_FIELD"
            assert_range [r httl myhash FIELDS 1 f1] 9900 10000
            assert_equal [r httl myhash FIELDS 1 f2] "$T_NO_EXPIRY"
        }

        test "HSETF - Test 'GT' flag ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2 f3 v3
            assert_equal [r hsetf myhash EX 1000 NX FVS 1 f1 n1] "$S_FIELD_AND_TTL"
            assert_equal [r hsetf myhash EX 2000 NX FVS 1 f2 n2] "$S_FIELD_AND_TTL"
            assert_equal [r hsetf myhash EX 1500 GT FVS 2 f1 n1 f2 n2] "$S_FIELD_AND_TTL $S_FIELD"
            assert_range [r httl myhash FIELDS 1 f1] 1400 1500
            assert_range [r httl myhash FIELDS 1 f2] 1600 2000
        }

        test "HSETF - Test 'LT' flag ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2 f3 v3
            assert_equal [r hsetf myhash EX 1000 NX FVS 1 f1 v1] "$S_FIELD_AND_TTL"
            assert_equal [r hsetf myhash EX 2000 NX FVS 1 f2 v2] "$S_FIELD_AND_TTL"
            assert_equal [r hsetf myhash EX 1500 LT FVS 2 f1 v1 f2 v2] "$S_FIELD $S_FIELD_AND_TTL"
            assert_range [r httl myhash FIELDS 1 f1] 900 1000
            assert_range [r httl myhash FIELDS 1 f2] 1400 1500

            # A field with no expiration is treated as an infinite expiration.
            # LT should set the expire time if field has no TTL.
            r del myhash
            r hset myhash f1 v1
            assert_equal [r hsetf myhash EX 1500 LT FVS 1 f1 v1]  "$S_FIELD_AND_TTL"
        }

        test "HSETF - Test 'EX' flag ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2
            assert_equal [r hsetf myhash EX 1000 FVS 1 f3 v3 ] "$S_FIELD_AND_TTL"
            assert_range [r httl myhash FIELDS 1 f3] 900 1000
        }

        test "HSETF - Test 'EXAT' flag ($type)" {
            r del myhash
            r hset myhash f1 v1 f2 v2
            assert_equal [r hsetf myhash EXAT 4000000000 FVS 1 f3 v3] "$S_FIELD_AND_TTL"
            assert_range [expr [r httl myhash FIELDS 1 f3] + [clock seconds]] 3900000000 4000000000
        }

        test "HSETF - Test 'PX' flag ($type)" {
            r del myhash
            assert_equal [r hsetf myhash PX 1000000 FVS 1 f3 v3] "$S_FIELD_AND_TTL"
            assert_range [r httl myhash FIELDS 1 f3] 990 1000
        }

        test "HSETF - Test 'PXAT' flag ($type)" {
            r del myhash
            r hset myhash f1 v2 f2 v2 f3 v3
            assert_equal [r hsetf myhash PXAT 4000000000000 FVS 1 f2 v2] "$S_FIELD_AND_TTL"
            assert_range [expr [r httl myhash FIELDS 1 f2] + [clock seconds]] 3900000000 4000000000
        }

        test "HSETF - Test 'KEEPTTL' flag ($type)" {
            r del myhash

            r hsetf myhash FVS 2 f1 v1 f2 v2
            r hsetf myhash PX 5000 FVS 1 f2 v2

            # f1 does not have ttl
            assert_equal [r httl myhash FIELDS 1 f1] "$T_NO_EXPIRY"

            # f2 has ttl
            assert_not_equal [r httl myhash FIELDS 1 f2] "$T_NO_EXPIRY"

            # Validate KEEPTTL preserve TTL
            assert_equal [r hsetf myhash KEEPTTL FVS 1 f2 n2] "$S_FIELD"
            assert_not_equal [r httl myhash FIELDS 1 f2] "$T_NO_EXPIRY"
            assert_equal [r hget myhash f2] "n2"
        }

        test "HSETF - Test no expiry flag discards TTL ($type)" {
            r del myhash

            r hsetf myhash FVS 1 f1 v1
            r hsetf myhash PX 5000 FVS 1 f2 v2

            assert_equal [r hsetf myhash FVS 2 f1 v1 f2 v2] "$S_FIELD $S_FIELD_AND_TTL"
            assert_not_equal [r httl myhash FIELDS 1 f1 f2] "$T_NO_EXPIRY $T_NO_EXPIRY"
        }

        test "HSETF - Test 'GETNEW/GETOLD' flag ($type)" {
            r del myhash

            assert_equal [r hsetf myhash GETOLD fvs 2 f1 v1 f2 v2] "{} {}"
            assert_equal [r hsetf myhash GETNEW fvs 2 f1 v1 f2 v2] "v1 v2"
            assert_equal [r hsetf myhash GETOLD fvs 2 f1 n1 f2 n2] "v1 v2"
            assert_equal [r hsetf myhash GETOLD DOF fvs 2 f1 n1 f2 n2] "n1 n2"
            assert_equal [r hsetf myhash GETNEW DOF fvs 2 f1 n1 f2 n2] "n1 n2"
            assert_equal [r hsetf myhash GETNEW DCF fvs 2 f1 x1 f2 x2] "x1 x2"
            assert_equal [r hsetf myhash GETNEW DCF fvs 2 f4 x4 f5 x5] "{} {}"

            r del myhash
            assert_equal [r hsetf myhash GETOLD fvs 2 f1 v1 f2 v2] "{} {}"

            # DOF check will prevent override and GETNEW should return old value
            assert_equal [r hsetf myhash DOF GETNEW fvs 2 f1 v12 f2 v22] "v1 v2"
        }

        test "HSETF - Test with active expiry" {
            r del myhash
            r debug set-active-expire 0

            r hsetf myhash PX 10 FVS 5 f1 v1 f2 v2 f3 v3 f4 v4 f5 v5
            r debug set-active-expire 1
            wait_for_condition 50 20 { [r EXISTS myhash] == 0 } else { fail "'myhash' should be expired" }
        }

        test "HSETF - Set time in the past ($type)" {
            r del myhash
            assert_equal [r hsetf myhash EXAT [expr {[clock seconds] - 1}] FVS 2 f1 v1 f2 v2] "$S_FIELD_AND_TTL $S_FIELD_AND_TTL"
            assert_equal [r hexists myhash field1] 0

            # Try with override
            r hset myhash fvs 2 f1 v1 f2 v2
            assert_equal [r hsetf myhash EXAT [expr {[clock seconds] - 1}] FVS 2 f1 v1 f2 v2] "$S_FIELD_AND_TTL $S_FIELD_AND_TTL"
            assert_equal [r hexists myhash field1] 0
        }

        test "HSETF - Test failed hsetf call should not leave empty key ($type)" {
            r del myhash
            # This should not create the field as DCF flag is given
            assert_equal [r hsetf myhash DCF FVS 1 a b] ""

            # Key should not exist
            assert_equal [r exists myhash] 0

            # Try with GETNEW/GETOLD
            assert_equal [r hsetf myhash GETNEW DCF FVS 1 a b] ""
            assert_equal [r exists myhash] 0
            assert_equal [r hsetf myhash GETOLD DCF FVS 1 a b] ""
            assert_equal [r exists myhash] 0
        }

        test {DUMP / RESTORE are able to serialize / unserialize a hash} {
            r config set sanitize-dump-payload yes
            r hmset myhash a 1 b 2 c 3
            r hexpireat myhash 2524600800 fields 1 a
            r hexpireat myhash 2524600801 fields 1 b
            set encoded [r dump myhash]
            r del myhash
            r restore myhash 0 $encoded
            assert_equal [lsort [r hgetall myhash]] "1 2 3 a b c"
            assert_equal [r hexpiretime myhash FIELDS 3 a b c] {2524600800 2524600801 -1}
        }

        test {DUMP / RESTORE are able to serialize / unserialize a hash with TTL 0 for all fields} {
            r config set sanitize-dump-payload yes
            r hmset myhash a 1 b 2 c 3
            r hexpire myhash 9999999 fields 1 a ;# make all TTLs of fields to 0
            r hpersist myhash fields 1 a
            assert_encoding $type myhash
            set encoded [r dump myhash]
            r del myhash
            r restore myhash 0 $encoded
            assert_equal [lsort [r hgetall myhash]] "1 2 3 a b c"
            assert_equal [r hexpiretime myhash FIELDS 3 a b c] {-1 -1 -1}
        }
    }

    r config set hash-max-listpack-entries 512
}

start_server {tags {"external:skip needs:debug"}} {

    # Tests that only applies to listpack

    test "Test listpack memory usage" {
        r hset myhash f1 v1 f2 v2 f3 v3 f4 v4 f5 v5
        r hpexpire myhash 5 FIELDS 2 f2 f4

        # Just to have code coverage for the new listpack encoding
        r memory usage myhash
    }

    test "Test listpack object encoding" {
        r hset myhash f1 v1 f2 v2 f3 v3 f4 v4 f5 v5
        r hpexpire myhash 5 FIELDS 2 f2 f4

        # Just to have code coverage for the listpackex encoding
        assert_equal [r object encoding myhash] "listpackex"
    }

    test "Test listpack debug listpack" {
        r hset myhash f1 v1 f2 v2 f3 v3 f4 v4 f5 v5

        # Just to have code coverage for the listpackex encoding
        r debug listpack myhash
    }

    test "Test listpack converts to ht and passive expiry works" {
        set prev [lindex [r config get hash-max-listpack-entries] 1]
        r config set hash-max-listpack-entries 10
        r debug set-active-expire 0

        r hset myhash f1 v1 f2 v2 f3 v3 f4 v4 f5 v5
        r hpexpire myhash 5 FIELDS 2 f2 f4

        for {set i 6} {$i < 11} {incr i} {
            r hset myhash f$i v$i
        }
        after 50
        assert_equal [lsort [r hgetall myhash]] [lsort "f1 f3 f5 f6 f7 f8 f9 f10 v1 v3 v5 v6 v7 v8 v9 v10"]
        r config set hash-max-listpack-entries $prev
        r debug set-active-expire 1
    }

    test "Test listpack converts to ht and active expiry works" {
        r del myhash
        r debug set-active-expire 0

        r hset myhash f1 v1 f2 v2 f3 v3 f4 v4 f5 v5
        r hpexpire myhash 10 FIELDS 1 f1

        for {set i 0} {$i < 2048} {incr i} {
            r hset myhash f$i v$i
        }

        for {set i 0} {$i < 2048} {incr i} {
            r hpexpire myhash 10 FIELDS 1 f$i
        }

        r debug set-active-expire 1
        wait_for_condition 50 20 { [r EXISTS myhash] == 0 } else { fail "'myhash' should be expired" }
    }

    test "HSETF - Test listpack converts to ht" {
        r del myhash
        r debug set-active-expire 0

        # Check expiry works after listpack converts ht by using hsetf
        for {set i 0} {$i < 1024} {incr i} {
            r hsetf myhash PX 10 FVS 3 a$i b$i c$i d$i e$i f$i
        }

        r debug set-active-expire 1
        wait_for_condition 50 20 { [r EXISTS myhash] == 0 } else { fail "'myhash' should be expired" }
    }

    test "HPERSIST/HEXPIRE - Test listpack with large values" {
        r del myhash

        # Test with larger values to verify we successfully move fields in
        # listpack when we are ordering according to TTL. This config change
        # will make code to use temporary heap allocation when moving fields.
        # See listpackExUpdateExpiry() for details.
        r config set hash-max-listpack-value 2048

        set payload1 [string repeat v3 1024]
        set payload2 [string repeat v1 1024]

        # Test with single item list
        r hset myhash f1 $payload1
        assert_equal [r hgetf myhash EX 2000 FIELDS 1 f1] $payload1
        r del myhash

        # Test with multiple items
        r hset myhash f1 $payload2 f2 v2 f3 $payload1 f4 v4
        r hexpire myhash 100000 FIELDS 1 f3
        r hpersist myhash FIELDS 1 f3
        assert_equal [r hpersist myhash FIELDS 1 f3] $P_NO_EXPIRY

        r hpexpire myhash 10 FIELDS 1 f1
        after 20
        assert_equal [lsort [r hgetall myhash]] [lsort "f2 f3 f4 v2 $payload1 v4"]

        r config set hash-max-listpack-value 64
    }
}