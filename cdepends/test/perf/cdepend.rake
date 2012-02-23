$: << File.join(File.dirname(__FILE__), "../..")

require 'cdepends'
require 'libgen'

libgen = LibGen.new(10, 40)
libgen.create_tasks
libgen.libs.each do |lib|
  include_dirs = lib.include_dirs
  dir = "tmp/objs"
  lib.sources.each do |src|
    target = lib.obj_file(src)
    cobject(target => [src, dir], :includes => include_dirs) do |t|
      touch t.name
    end
  end
end
