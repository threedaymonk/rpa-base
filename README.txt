

Please read manifesto.txt for information about RPA's goals, which go far
beyond rpa-base.

** keep in mind that this is *not* a RPA release (including the repository)
   but just a release of the rpa-base tool; we have provided some sample
   ports/packages for testing purposes, but they're not yet managed as part of
   the RPA process **

rpa-base is a port/package manager created to be the base for RPA's
client-side package management. You can think of it as RPA's apt-get + dpkg.
It features the following:
 * modular, extensible design: the 2-phase install is similar to FreeBSD and
   Debian's package creation; rpa-base packages need not be restricted
   to installing everything under a single directory ("1 package, 1 dir"
   paradigm); this will be useful when we define the RPA Policy
 * sane dependency management: rpa-base installs dependencies as needed,
   keeps track of reverse dependencies on uninstall, and will remove no
   longer needed dependencies (e.g. you install A, which depends on B,
   so B gets installed and then A; when you later remove A, rpa-base
   will realize B is not longer needed and remove it too).
 * atomic (de)installs: operations on the local RPA installation are atomic
   transactions; the system has been designed to survive ruby crashes (OS
   crashes too on POSIX systems), which means that a port is either altered
   successfully or the system rolls back to the previous clean state
 * handling C extensions: if you have the required C toolchain, rpa-base can
   compile extensions as needed
 * API safety: all libraries within a RPA release will be guaranteed to be
   API-compatible; by tying your local applications to specific versions of
   RPA, they're protected from API breakage. You'll be able to install several
   RPA releases simultaneously without problems.
 * rdoc integration: RDoc documentation for libraries is generated at install
   time (currently put in $prefix/share/doc/rpa0.0/portname)
 * unit testing: when a library is installed, its unit tests are run; the
   installation is canceled if they don't pass
 * ri integration: ri data files are generated for all the libraries managed
   by RPA; you can access this information with ri-rpa


Installing
==========
  ruby install.rb

NOTE TO DEBIAN USERS:

Debian splits Ruby's standard distribution into a miriad of packages; rpa-base
assumes that the standard components are installed and will fail if you don't
have them.

The required packages include
  rdoc1.8
  libtest-unit-ruby1.8
  libyaml-ruby1.8
  libzlib-ruby1.8

besides ruby1.8, of course.

Running the unit tests
======================
  cd test
  ruby tc_all.rb

Using rpa
=========

Take a look at rpa's options by running
  rpa

You can take a look at the available ports with
  rpa update
  rpa query 

Installing stuff
-----------------
  rpa install example
  rpa install instiki

Removing
--------
  rpa remove example

Ri integration
--------------

To access the ri data files managed by RPA, you'll need to install the ri-rpa
port:

  rpa install ri-rpa

Please note that this will take a while since that package is pretty big
(around 13MB since it includes the ri info taken from the 1.9 CVS sources),
but you'll only have to install it once.

You can access Ruby's standard documentation with ri-rpa:

  ri-rpa Class

After installing a port with rpa-base, you can get its info using ri-rpa too:

  rpa install keyedlist
  ri-rpa --port keyedlist KeyedList

Transactions
------------

Both install and remove are transacted; either they succeed or partial changes 
are undone. The system guarantees that you won't lose a port when upgrading
it: if some error were detected in the new version, the older one will be
restored automatically.

You can also install a number of ports as a transaction:
 
 rpa install instiki redcloth hashslice

will either install/upgrade all those ports or none.

For extra fun, try killing the process (CTRL-C will do) while it is doing a
transaction (install or remove), and see it rollback automatically. If you
kill the process while it's rolling back, you can still recover with
  rpa rollback
which will restore the previous clean state. A rollback is performed
automatically when installing/removing a port if the system detects an
unclean state.
