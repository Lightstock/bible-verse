module BibleBot
  # This class is contains all the logic for mapping the different parts of a scripture Match into an actual {Reference}.
  # It wraps the Match returned from the regular expression defined in {Bible.scripture_re}.
  #
  # A scripture reference can take many forms, but the least abbreviated form is:
  #
  #   Genesis 1:1 - Genesis 1:2
  #
  # Internally, this class represents this using the following variables:
  #
  #   b1 c1:v1 - b2 c2:v2
  #
  # See Readme for list of supported abbreviation rules.
  #
  # == Advanced Use Cases
  #
  # This is a low level class used internally by {Reference.parse}.
  # There are however some advanced use cases which you might want to use it for.
  # For example, if you want to know where in the parsed String certain matches occur.
  #
  # For this there are a few convenience attributes:
  #
  # * {#match}
  # * {#length}
  # * {#offset}
  #
  # @example
  #   matches = ReferenceMatch.scan("Mark 1:5 and another Romans 4:1")
  #   matches[0].match[0]   #=> "Mark 1:5"
  #   matches[0].offset     #=> 0
  #   matches[0].length     #=> 8
  #   matches[0].match[0]   #=> "Romans 4:1"
  #   matches[1].offset     #=> 21
  #   matches[1].length     #=> 10
  #
  # @note You shouldn't need to use this class directly. For the majority of use cases, just use {Reference.parse}.
  class ReferenceMatch
    attr_reader :match # @return [Match] The Match instance returned from the Regexp
    attr_reader :length # @return [Integer] The length of the match in the text string
    attr_reader :offset # @return [Integer] The starting position of the match in the text string

    # Converts a string into an array of ReferenceMatches.
    # Note: Does not validate References.
    #
    # @param text [String]
    # @return [Array<ReferenceMatch>]
    def self.scan(text)
      scripture_reg = Bible.scripture_re
      Array.new.tap do |matches|
        text.scan(scripture_reg){ matches << self.new($~, $~.offset(0)[0]) }
      end
    end

    # @return [Reference]
    def reference
      @reference ||= Reference.new(
        start_verse: Verse.new(book: start_book, chapter_number: start_chapter.to_i, verse_number: start_verse.to_i),
        end_verse: Verse.new(book: end_book, chapter_number: end_chapter.to_i, verse_number: end_verse.to_i),
      )
    end

    private

    attr_reader :b1 # @return [String]
    attr_reader :c1 # @return [String] Represents the number after the start Book name, could be either chapter or verse number.
    attr_reader :v1 # @return [String, nil] Represents the number after the colon, will always be start_verse if present.
    attr_reader :b2 # @return [String, nil]
    attr_reader :c2 # @return [String, nil] Represents the number after the end Book name, could be either chapter or verse number.
    attr_reader :v2 # @return [String, nil] Represents the number after the colon, will always be end_verse if present.

    def initialize(match, offset)
      @match = match
      @length = match.to_s.length
      @offset = offset
      @b1 = match[:BookTitle]
      @c1 = match[:ChapterNumber]
      @v1 = match[:VerseNumber]
      @b2 = match[:EndBookTitle]
      @c2 = match[:EndChapterNumber]
      @v2 = match[:EndVerseNumber]
    end

    def start_book
      # There will always be a starting book.
      Book.find_by_name(@b1)
    end

    def end_book
      # The end book is optional. If not provided, it is assumed it is the same as the starting book.
      Book.find_by_name(@b2) || start_book
    end

    def start_chapter
      # Start chapter should always be provided, except in the case of single chapter books.
      return 1 if start_book.single_chapter?
      c1
    end

    def start_verse
      # Start verse should always be provided.
      # The one exception is that for single chapter books, the verse might be in the chapter's place, and v1 is nil.
      v1 || (start_book.single_chapter? ? c1 : 1)
    end

    def end_chapter
      return start_chapter if single_verse_ref? # Ex: Genesis 1:3 => "1"
      return 1 if end_book.single_chapter? # Ex: Jude 2-4 => "1"
      return c1 if !b2 && !v2 && v1  # Ex: Genesis 1:2-3 => "1"
      c2 ||   # Ex: Genesis 1:1 - 2:4 => "4"
      c1      # Ex: Genesis 5 => "5"
    end

    def end_verse
      return start_verse if single_verse_ref? # Ex: Genesis 1:3 => "3"
      v2 || # Ex: Genesis 1:4 - 2:5 => "5"
      (
        (v1 && !b2) ?
        c2 : # Ex: Gen 1:4-8  => "8"
        end_book.chapters[end_chapter.to_i - 1] # Genesis 1 => "31"
      )
    end

    # If there is no match for b2, c2, or v2
    def single_verse_ref?
      !b2 && !c2 && !v2 &&
      (v1 || start_book.single_chapter?) # Ex: Genesis 5:1 || Jude 5
    end
  end
end
