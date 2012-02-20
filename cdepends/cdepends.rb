# TODO:
#  - Handle case insensitivity
#  - Documentation
#  - Allow makedepends to plugin
#  - String param to allow name of depends file to be specified
#
#  Cool things makedepends does:
#  - Remove extra .. from pathname (Handling symbolic links)
#  - Files already expanded don't need to be expanded again.
#    Because we don't save include paths between src files we
#    would need a negative list of header files that were already
#    checked but don't exist.
#  - Parse all preprocessor instructions.
#  - Check for anything else...
#
#  Bad things about rake's import/makedepends method:
#  - Dependancies generated even when you specify a target that does
#    not need them.

# Add task search function to rake.
# This is different from lookup() because it will try to create the
# task from rules.  It does not try to create a file task as we want
# to use our special fast file task for a speed inprovement.
# It is similar to [] except that it does not cause an abort if the
# task is not found.
class Rake::Application
  def find_task(task_name, scopes=nil)
    task_name = task_name.to_s
    self.lookup(task_name, scopes) or
      enhance_with_matching_rule(task_name)
  end
end

# File task with timestamp speedup.  The regular file task will query
# the File.mtime for every task that depends on this file.  Typically
# when compiling c/c++ some header files are included very often, and
# if a a regular file task is used to represent header files then the
# File.mtime function will be called each time a source file depends
# on the header.  By caching the timestamp we insure that this
# operation occurs only once for each header file.
#
# NOTE: Caching the timestamp may cause problems if the file is
# generated/updated by another task as a side effect.
#
class Rake::FastFileTask < Rake::FileTask
  # Time stamp for file task.
  def timestamp
    # Cache the timestamp since it is accessed often
    if instance_variable_defined?(:@timestamp)
      @timestamp
    else
      # exist? and mtime can be done together with one call to
      # File.stat, but for some reason this takes longer on Windows.
      # Ruby is probably making several Win32 calls.  Opimization
      # would be to call GetFileAttributesEx() directly.  Using
      # Win32API module this is slightly faster, making the call via
      # a c extension would probably be faster again.
      if File.exist?(name)
        @timestamp = File.mtime(name.to_s)
        # Update the time stamp when the task is executed
        enhance do
          @timestamp = Time.now
        end
        @timestamp
      else
        # Build me!
        Rake::EARLY
      end
    end
  end
end

class Rake::CParser
  def self.parse_file_includes file
    parse_includes File.read(file)
  end

  # quick and dirty method of extracting include files
  # from a source file.
  def self.parse_includes src
    includes = []
    src.gsub!(/\/\*(?:.*?)\*\//m, "")
    unparsed_lines = ""
    src.lines.each { |line|
      line = unparsed_lines + line
      case line
      when /^\s*(#\s*include\s+)\\$/
        # save continued line
        unparsed_lines += $1
      when /^\s*#\s*include\s+"([^"]+)"/
        includes << $1
        unparsed_lines = ""
      when /^\s*#\s*include\s+<([^>]+)>/
        includes << $1
        unparsed_lines = ""
      end
    }
    includes
  end

end

# A basic c/c++ dependancy generator.
#
# The basic idea is taken from 'automake'.  See 'Advanced
# Auto-Dependency Generation' at:
#
#   http://make.paulandlesley.org/autodep.html
#
# The difference is we generate the dependacies using ruby, which
# allows us to be faster and more portable than using the compiler
# or 'makedepends'.
#
# NOTE: This class doesn't process macros or ifdefs.  All
# includes that can be found are added as dependancies.  This can
# cause some extra rebuilds when include files are not used by
# the compiler because they are #ifdef'ed out.  The advantage of
# this is that we have a faster dependancy generator and don't
# need a list of user and bcompiler built in defines to process
# the includes.
#
# TODO: I'm guessing the speed hit from generating an
# accurate list would be acceptable though...
#
class Rake::CDependGenerator
  attr_reader :file

  # Create a new dependancy list
  # If the given file exists it is read.
  # When exiting all the updates to the dependancy list
  # are written to this file
  def initialize file
    @file = file
    @new_depends = {}
    @source_files = []
    @flat_depends = {}

    if File.exist? @file
      load_depends @file
    end

    # If the clean target is defined add the dependancy file
    # to it.
    if defined? CLEAN && CLEAN.is_a(Rake::FileList)
      CLEAN.add @file
    end

    # Save the dependancies at exit if they have changed
    # since last invocation.
    at_exit do
      if has_changes?
        write_depends
      end
    end
  end

  # Return all dependancies for given source file
  # Source files are used rather than object files
  # This allows for some optimizations, if we assume
  # all files in a dependancy list are compiled with
  # the same options we only need to parse each header
  # file once.
  def [] file
    depends = @flat_depends[file]
    if depends == nil
      [file]
    else
      depends
    end
  end

  # Have any new dependancies been added via 'update()'?
  def has_changes?
    @source_files.size > 0
  end

  def has_depends? file
    @flat_depends[file] != nil
  end

  # Update dependancies for the given file and for any includes
  # that it points to.
  def update include_dirs, source
    if not @source_files.include? source
      @source_files << source
    end
    update_depends include_dirs, source
  end

  # Write out the dependancy cache
  def write_depends
    @source_files.each { |file|
      depends = []
      flatten_depends depends, file
      @flat_depends[file] = depends
    }
    FileUtils.mkdir_p File.dirname(@file)
    File.open(@file, 'w') { |f|
      @flat_depends.each { |src, deps|
        f << "add_dep '#{src}', ["
        if deps and not deps.empty?
          f << "'#{deps.join("', '")}'" end
        f << "]\n"
      }
      f << "\n"
    }
  end

private
  # Recursively find all files included in +file+ from the
  # dependancy cache.
  def flatten_depends clist, file
    clist << file
    depends = @new_depends[file]
    if depends
      depends.each { |dep|
        unless clist.include? dep
          flatten_depends clist, dep
        end
      }
    end
  end

  # Recalculate dependancies for file +src+
  def update_depends include_dirs, src
    if not @new_depends.has_key? src
      includes = find_includes include_dirs, src
      @new_depends[src] = includes

      # Add any new includes to list for scanning 
      if includes
        includes.each { |inc|
          update_depends include_dirs, inc
        }
      end
    end
  end

  # Return file list containing paths to files included in +src+
  def find_includes include_dirs, src
    includes = Rake::CParser.parse_file_includes src
    res = includes.collect { |inc|
      search_includes include_dirs, src, inc
    }
    res.compact
  end

  def search_includes include_dirs, src, file
    # Check include paths for file
    include_dirs.each { |dir|
      path = File.join(dir, file)
      if file_task? path
        return path
      end
    }

    # Check in source files directory.
    # Source directory doesn't need to be in
    # +include_dirs+.
    path = File.join(File.dirname(src), file)
    if file_task? path
       return path
    end
    nil
  end

  # Returns true if the file exists or a task exists
  # to generate the file.
  def file_task? path
    task = Rake.application.find_task path
    if not task
      if File.exists? path
        task = Rake.application.define_task(Rake::FastFileTask, path)
      end
    end
    if task
      # Generate file so it can be processed for includes
      # as well.
      task.invoke
      true
    else
      false
    end
  end

  # Called by dependancy file to add dependancies to this object.
  def add_dep file, deps
    @flat_depends[file] = deps
  end

  # Read dependancy file 
  def load_depends file
    # The depends file is valid ruby, no need to use our own parser.
    instance_eval File.read(file), file
  end
end

class Rake::CObjectTask < Rake::FileTask
  attr_accessor :includes
  attr_accessor :depends

  def self.define_task(*args, &block)
    includes = args[0].delete :includes
    depends = args[0].delete :depends
    if not depends
      if not @depends
        @depends = Rake::CDependGenerator.new '.rake_cdepends.rb'
      end
      depends = @depends
    end

    task = super
    task.depends = depends
    task.includes = includes
    task
  end

  def invoke_prerequisites *arg
    src = prerequisites.first
    if depends.has_depends? src
      enhance depends[src] do depends.update(includes, src) end
    else
      depends.update(includes, src)
      enhance depends[src]
    end
    depends[src].each { |preq| 
      if not application.find_task preq
        application.define_task(Rake::FastFileTask, preq)
      end
    }
    super
  end
end

# Declare a C/C++ object task.
#
# Example:
#  cobject('source.obj' => 'source.cpp', :includes => %w(inc)) do |t|
#    inc_flags = t.includes.map { |i| '-I ' + i }.join ' '
#    sh 'gcc -c ' + t.source ' -o' + t.name + ' ' + inc_flags
#  end
#
def cobject(args, &block)
  Rake::CObjectTask.define_task(args, &block)
end
