#
# NOTE:
# - depends file must be generated each time the script is executed not matter
#   cpp files you compile.
#
# - src files must exist before file is created
#
require 'rake/loaders/makefile'
require 'libgen'

libgen = LibGen.new(10, 40)
libgen.create_tasks
libgen.libs.each do |lib|
  include_dirs = lib.include_dirs
  cflags = ""
  if include_dirs.size > 0
    cflags = "-I " + include_dirs.join(" -I")
  end
  dir = "tmp/objs"
  lib.sources.each do |src|
    target = lib.obj_file(src)
    file(target => [src, dir]) do |t|
      touch t.name
    end
  end
  file ".depends.mf" => lib.sources do |t|
    sh "makedepend -f- -pobjs/ -- #{cflags} -- #{lib.sources.join(' ')} >> #{t.name}" 
  end
end

import ".depends.mf" 
