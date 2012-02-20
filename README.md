RakeCpp
=======
Rake helper classes for building c/c++ projects.

cdepends
--------

Header dependency management to allow incremental builds, so that c/c++ file that need to be build always are.  This is an all Ruby alternative to using makedepends.  Advantages are that it is faster than makedepends and more correct (the rake way of using makedepends has problems with generated files, and requires makedepends to be rerun when the header list changes).

Usage:

  require 'cdepends'

  cobject('source.o' => ['source.cpp'],
          :includes => %w(inc) do |t|
    # Command to build source.o
  end

minusj
------

Emulates make -j in rake.  Tasks can be setup to be built in parallel.  Useful for splitting compiles over multiple processors.

Usage:

Just add the following to your 'rakefile':

  require 'minusj'

Then build any task from from the command line as follows:

  > rake threads=4

This requires stricter dependencies than running tasks sequentially, just like it does in make.  Multiple dependencies will be evaluated at the same time.

