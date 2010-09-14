#!/usr/bin/env ruby

require 'set'
require 'find'

class Project
  IGNORED_DIRS = %w(autom4te.cache blib _build .bzr .cdv cover_db CVS _darcs ~.dep ~.dot .git .hg ~.nib .pc ~.plst RCS SCCS _sgbak .svn)

  IGNORED_FILES = [
    /~$/,           # Unix backup files
    /\#.+\#$/,      # Emacs swap files
    /core\.\d+$/,   # core dumps
    /[._].*\.swp$/, # Vi(m) swap files
  ]

  def initialize(path=nil)
    self.root = path && File.expand_path(path) || Dir.pwd
  end

  def root=(path)
    path = path[0..-2] if path.end_with?("/")
    if path != @root
      @root = path
      scan_root
    end
  end

  def scan_root
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
  end

  def files_with_characters(chars)
    result = @char_to_path_map[chars[0]]
    chars[1..-1].each_char do |char|
      result = @char_to_path_map[char] & result
    end
    result
  end

  def search(chars)
    # Search.new(files_with_characters(chars), chars).result
    Search.new(@paths, chars).result
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
      elem[:score] = dist + (now - File.mtime(elem[:path])).to_f / 86400.0
    end
  end

  def result
    pattern = "^(?:[_.])?"
    @chars.each_char do |char|
      pattern << "(#{Regexp.escape(char)}).*?"
    end
    regexp = Regexp.new(pattern)

    matches = []
    puts @set.size
    @set && @set.each do |path|
      if m = File.basename(path).match(regexp)
        matches << { :matcher => m, :path => path }
      end
    end

    sorted(matches)
  end
end

project = Project.new(ARGV.first)

begin
  while (line = STDIN.readline.strip)
    if line =~ /^setroot (.*)/
      project.root = $1
    elsif line =~ /^search (.*)/
      start = Time.now
      result = project.search($1)
      puts Time.now - start
      result.each_with_index do |e, i|
        puts "#{File.basename(e[:path])}|#{e[:path]}|#{e[:score]}" # TODO: mark matched chars
      end
      puts
      STDOUT.flush
    end
  end
rescue EOFError
end
