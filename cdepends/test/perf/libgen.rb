class CppLib
  attr_reader :name, :libs
  def initialize name, libs, num_classes
    @name = name
    @libs = libs
    @num_classes = num_classes
  end

  def dir
    "tmp/#{@name}"
  end

  def include_dirs
    includes = []
    @libs.each { |lib|
      includes << lib.dir
    }
    includes
  end

  def random_includes
    includes = []
    rand(@num_classes).times do |i|
      header = @name + '_class' + rand(@num_classes).to_s + '.h'
      includes << header
    end
    includes.uniq
  end

  def write
    FileUtils.mkdir_p dir
    @num_classes.times do |i|
      write_header i
      includes = random_includes
      @libs.each { |lib|
        includes += lib.random_includes
      }
      write_cpp(i, includes)
    end
  end

  def sources
    a = []
    @num_classes.times do |i| a << cpp_file(i) end
    a
  end

  def class_name i
    @name + '_class' + i.to_s
  end

  def h_file i
    File.join(dir, class_name(i) + '.h')
  end

  def cpp_file i
    File.join(dir, class_name(i) + '.cpp')
  end

  def obj_file src
    obj = File.join('tmp/objs', File.basename(src).ext('o'))
  end

  def write_header i
    filename = h_file i
    name = class_name i
    File.open(filename, 'w') { |file|
      guard = name + '_h_'
      file << "#ifndef #{guard}\n"
      file << "#define #{guard}\n"
      file << "\n"
      file << "class #{name} {\n"
      file << "public:\n"
      file << "  #{name}();\n"
      file << "  ~#{name}();\n"
      file << "};\n\n"
      file << "#endif\n"
    }
  end

  def write_cpp i, includes
    filename = cpp_file i
    name = class_name i
    File.open(filename, 'w') { |file|
      file << "#include \"#{name}.h\"\n"
      file << "\n"
      includes.each { |inc|
        file << "#include \"#{inc}\"\n"
      }
      file << "\n"
      file << "#{name}::#{name}() { }\n"
      file << "#{name}::~#{name}() { }\n"
      file << "\n\n"
    }
  end
end

class LibGen
  attr_reader :libs

  def initialize num_libs, files_per_lib
    @num_libs = num_libs
    @files_per_lib = files_per_lib
    @libs = []
    @num_libs.times do |i|
      lib = CppLib.new 'lib' + i.to_s, libs.dup, files_per_lib
      libs << lib
    end
  end

  def create_tasks
    directory 'tmp/objs'

    task :clean do
      rm_rf 'tmp/objs'
    end

    desc "Generate library source files"
    task :gensrc do
      @libs.each do |lib|
        lib.write
      end
    end

    desc "Build sources"
    @libs.each { |lib|
      objs = []
      lib.sources.each { |src|
        obj = lib.obj_file(src)
        objs << obj
      }
      task :build => objs
    }

    task :clobber => :clean do
      @libs.each do |lib| rm_rf lib.dir end
    end

    task :default => [:gensrc, :build]
  end
end
