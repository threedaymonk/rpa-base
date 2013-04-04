#!/usr/bin/env ruby

$:.unshift ".."
$".unshift "tc_all.rb"
puts <<EOF
This test will take a while to complete (around 30 seconds on a K7
1700XP+ machine on Linux, around 90 on win32), since it runs a number of
transactions (200 currently) and verifies the integrity of the system.

Every once in a while, a bug in syck/ruby (endless loop in the
interpreter) is triggered and causes the tests to hang; just kill the
process in that case. Note that rpa-base is designed to survive ruby
crashes (and depending on your system, it will also survive OS crashes),
so if this were to happen while using rpa (we hope syck will be fixed
though), just kill the process and rpa will roll back on the next run.
EOF
Dir["tc_*.rb"].each {|f| require f}

