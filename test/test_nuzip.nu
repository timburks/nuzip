;; test_nuzip.nu
;;  tests for NuZip.
;;
;;  Copyright (c) 2008 Tim Burks, Neon Design Technology, Inc.

(load "NuZip")

(class TestNuZip is NuTestCase
     
     (- testUnzip is
        (system "rm -rf nuzip_test.zip nuzip_test tmp")
        (system "mkdir nuzip_test")
        (system "ls > nuzip_test/ls")
        (system "printenv > nuzip_test/printenv")
        (system "zip -r nuzip_test.zip nuzip_test")
        (system "mkdir tmp")
        (NuZip unzip:"-q nuzip_test.zip -d tmp")
        (assert_equal 0 (system "diff -r nuzip_test tmp/nuzip_test"))))








