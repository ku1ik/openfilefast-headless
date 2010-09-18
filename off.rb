#!/usr/bin/env ruby

require 'set'
require 'find'

module OpenFileFast

  class Directory
    IGNORED_DIRS = %w(autom4te.cache blib _build .bzr .cdv cover_db CVS _darcs ~.dep ~.dot .git .hg ~.nib .pc ~.plst RCS SCCS _sgbak .svn)

    IGNORED_FILES = [
      /~$/,           # Unix backup files
      /\#.+\#$/,      # Emacs swap files
      /core\.\d+$/,   # core dumps
      /[._].*\.swp$/, # Vi(m) swap files
    ]

    attr_reader :rescan_needed

    def initialize(path=nil)
      @state = nil
      @root = path && File.expand_path(path) || Dir.pwd
      @root = @root[0..-2] if @root.end_with?("/")
      rescan
    end

    def schedule_rescan
      if @state == :rescan
        return
      elsif @state == :search
        @rescan_needed = true
        return
      else
        rescan
      end
    end

    def rescan
      @state = :rescan
      @paths = []

      Find.find(@root) do |path|
        if File.directory?(path)
          Find.prune if IGNORED_DIRS.include?(File.basename(path))
        else
          @paths << path unless IGNORED_FILES.any? { |pattern| path =~ pattern }
        end
      end

      @char_to_path_map = {}
      @paths.each do |path|
        File.basename(path).downcase.each_char do |char|
          set = (@char_to_path_map[char] ||= Set.new)
          set.add(path)
        end
      end

      @rescan_needed = false
      @state = nil
    end

    def files_with_characters(chars)
      result = @char_to_path_map[chars[0]]
      chars[1..-1].each_char do |char|
        result = @char_to_path_map[char] & result
      end
      result
    end

    def search(chars)
      @state = :search
      # Search.new(files_with_characters(chars), chars).result
      result = Search.new(@paths, chars).result
      @state = nil
      result
    end
  end

  class Search
    def initialize(set, chars)
      @set = set
      @chars = chars
    end

    def sorted(matches)
      now = Time.now
      matches.sort_by do |elem|
        matcher = elem[:matcher]
        dist = 0
        1.upto(matcher.size-2) do |i|
          dist += matcher.begin(i+1) - matcher.begin(i) - 1
        end
        elem[:score] = dist + (now - File.mtime(elem[:path])).to_f / 86400.0 # TODO: handle Errno::ENOENT
      end
    end

    def result
      pattern = "^(?:[_.])?"
      @chars.each_char do |char|
        pattern << "(#{Regexp.escape(char)}).*?"
      end
      regexp = Regexp.new(pattern)

      matches = []
      @set && @set.each do |path|
        if m = File.basename(path).match(regexp)
          matches << { :matcher => m, :path => path }
        end
      end

      sorted(matches)
    end
  end
end

if $0 == __FILE__
  directory = OpenFileFast::Directory.new(ARGV.first)

  Signal.trap("USR1") do
    directory.schedule_rescan
  end

  while !STDIN.eof?
    line = STDIN.readline.strip
    if line.size > 0
      result = directory.search(line)
      result.each_with_index do |e, i|
        puts "#{File.basename(e[:path])}|#{e[:path]}|#{e[:score]}" # TODO: mark matched chars
      end
    end
    puts
    STDOUT.flush
    directory.rescan if directory.rescan_needed
  end
end
