# frozen_string_literal: true

module Hashdiff
  # @private
  #
  # caculate array difference using LCS algorithm
  # http://en.wikipedia.org/wiki/Longest_common_subsequence_problem
  def self.lcs(arraya, arrayb, options = {})
    Lcs.call(arraya, arrayb, options)
  end

  # @private
  #
  # Finds the pairs [index in arraya, index in arrayb] of similar items that
  # make up the longest common subsequence of the two arrays, with Myers'
  # algorithm (http://www.xmailserver.org/diff2.pdf). For arrays of n and m
  # items its work grows with (n + m) * d, d being the number of items left
  # unpaired, and not with n * m. At worst it compares each pair of items
  # about once.
  #
  # A position [a_pos, b_pos] stands for the first a_pos items of arraya and
  # the first b_pos items of arrayb. Its cost is the fewest items that have to
  # be left unpaired to get there from [0, 0], and its diagonal is
  # a_pos - b_pos: pairing two items stays on the diagonal, leaving one
  # unpaired moves to the next diagonal.
  class Lcs
    def self.call(arraya, arrayb, options = {})
      return [] if arraya.empty? || arrayb.empty?

      new(arraya, arrayb, options).call
    end

    def call
      pair_common_suffix
      unless a_pos.zero? || b_pos.zero? # an array has no items left to pair
        explore
        backtrack
      end
      pairs.reverse
    end

    private

    attr_reader :arraya, :arrayb, :options, :pairs, :reached, :lowest
    # the position the backtrack is at, walking from the last items to the first
    attr_accessor :a_pos, :b_pos

    def initialize(arraya, arrayb, options)
      @arraya = arraya
      @arrayb = arrayb
      @options = { similarity: 0.8 }.merge!(options)
      @options[:prefix] = Hashdiff.prefix_append_array_index(@options[:prefix], '*', @options)
      @pairs = []
      @reached = [] # reached[cost]: the furthest a_pos that cost gets to on each diagonal
      @lowest = []  # lowest[cost]: the first of those diagonals, the others follow 2 apart
      self.a_pos = arraya.size
      self.b_pos = arrayb.size
    end

    # The backtrack starts at the last items and pairs them whenever they are
    # similar, so it always pairs the common suffix item by item. Pairing it
    # first leaves the search only the items before it.
    def pair_common_suffix
      pair_and_step while a_pos > 0 && b_pos > 0 && similar_at?(a_pos - 1, b_pos - 1)
    end

    # For each cost in turn, finds how far along each diagonal that cost
    # gets, until one gets to the backtrack's position. It compares each pair
    # of items at most once, and only the pairs a lower cost did not get past.
    #
    # A diagonal that gets to the end of arrayb is done, like the ones below
    # it, and so are the ones above a diagonal that gets to the end of arraya:
    # the way to the last items never goes through them again.
    #
    # This loop is where the time goes, hence the local variables.
    def explore
      a_items = arraya
      b_items = arrayb
      a_size = a_pos
      b_size = b_pos
      opts = options
      furthest = Array.new(a_size + b_size + 3, -1) # by diagonal + b_size + 1
      low_limit = -b_size
      cost = 0
      loop do
        low = cost < -low_limit ? -cost : low_limit + ((cost + low_limit) & 1)
        lowest << low
        reached << (row = [])
        above = furthest[low + b_size]
        diagonal = low
        while diagonal <= cost
          index = diagonal + b_size + 1
          below = above
          above = furthest[index + 1]
          a_at = below < above ? above : below + 1
          b_at = a_at - diagonal
          while a_at < a_size && b_at < b_size && Hashdiff.similar?(a_items[a_at], b_items[b_at], opts)
            a_at += 1
            b_at += 1
          end
          row << (furthest[index] = a_at)
          if a_at >= a_size
            return if b_at >= b_size

            break
          end
          low_limit = diagonal + 1 if b_at >= b_size
          diagonal += 2
        end
        cost += 1
      end
    end

    # Walks back to the first items. Where several subsequences are as long,
    # it takes the one a table of LCS lengths gives when its backtrack pairs
    # two similar items whenever it can.
    def backtrack
      cost = reached.size - 1
      while cost < a_pos + b_pos # the items before the position still have pairs
        if pair_before?(cost)
          pair_and_step
        else
          leave_one_unpaired(cost)
          cost -= 1
        end
      end
    end

    # Steps to the position before that the cost before gets to. When it gets
    # to both, it leaves the item of arraya unpaired.
    def leave_one_unpaired(cost)
      if a_pos - 1 <= reached_at(cost - 1, a_pos - b_pos - 1)
        self.a_pos = a_pos - 1
      else
        self.b_pos = b_pos - 1
      end
    end

    # Whether the two items before the backtrack's position are similar. The
    # search already knows for the ones it compared: those on the run of
    # similar items the cost made on this diagonal, and the one that stopped
    # this diagonal's run two costs earlier.
    def pair_before?(cost)
      diagonal = a_pos - b_pos
      from_below = reached_at(cost - 1, diagonal - 1)
      from_above = reached_at(cost - 1, diagonal + 1)
      return true if a_pos > (from_below < from_above ? from_above : from_below + 1)
      return false if a_pos - 1 == reached_at(cost - 2, diagonal)

      similar_at?(a_pos - 1, b_pos - 1)
    end

    # The furthest a_pos the cost gets to on the diagonal, -1 when it cannot
    # get to the diagonal at all. The backtrack only stands on a cheapest way
    # to the last items, so it never asks about a diagonal the search dropped.
    def reached_at(cost, diagonal)
      return -1 if diagonal.abs > cost

      reached[cost].fetch((diagonal - lowest[cost]) / 2)
    end

    def pair_and_step
      self.a_pos = a_pos - 1
      self.b_pos = b_pos - 1
      pairs << [a_pos, b_pos]
    end

    def similar_at?(index_a, index_b)
      Hashdiff.similar?(arraya[index_a], arrayb[index_b], options)
    end
  end
end
