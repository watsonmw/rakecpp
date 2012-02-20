RakeCpp
=======
Rake helper classes for building c/c++ projects.

cdepends
--------

Header dependency management to allow incremental builds of c/c++ projects.  This is an all Ruby alternative to 'makedepends'.  Advantages are that it is faster than makedepends and more accurate (the rake way of using makedepends has problems with generated header files, and requires makedepends to be rerun at when the included header list changes, or any of included headers themselves are changed to include new headers).

Usage:

   
    require 'cdepends'
   
    cobject('source.o' => ['source.cpp'],
            :includes => %w(inc) do |t|
     # Command to build source.o
    end
   

When 'source.o' is built a file '.rake_cdepends.rb' will be created with a list of header dependencies.  When any of these change, rake will consider 'source.o' as needing to be rebuilt.

NOTE: cdepends is not a full preprocessor, 'defines' are not evaluated or expanded.  Instead all includes are considered even if they are ifdef'ed out.  This is a problem sometimes (when includes are macro expanded) and an advantage others (when you are building for multiple platforms or changing defines often).

minusj
------

Allows multiple threads to be used when building rake tasks.  Emulates make -j in rake.  Useful for splitting compiles over multiple processors for example.

Usage:

Just add the following to your 'rakefile':

    require 'minusj'

Then build any task from from the command line as follows:

  > rake threads=4

NOTE: This requires stricter dependencies than running tasks sequentially, just like it does in make.  Multiple dependencies will be evaluated at the same time, which can cause builds to fail if the dependencies are not all correctly setup.
