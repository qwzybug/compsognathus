Shoes.setup do
  gem 'midiator'
end
require 'midiator'
require 'archaeopteryx/lib/archaeopteryx'

class MyArkx < Arkx
  attr_accessor :midi
end

class MyRhythm < Rhythm
  def initialize(attributes)
    @drummaker = attributes[:drummaker]
    reload
  end
  def reload
    @drums = @drummaker.drums
  end
end

Shoes.app :title => 'Bluesmachine', :width => 514, :height => 801 do
  $measures = 1
  $mutation = L{|measure|true}
  @clock = Clock.new(60)
  # 12-bar blues
  @mods = [0, 0, 0, 0,
           5, 5, 0, 0,
           7, 5, 0, 0]
  a = (0..4).map{|i| ([0,0] * i + [1.0,0] + [0,0] * (4-i))[0...8]}
  a = a.zip(a.reverse).map{|as| as[0] + as[1]}
  @notes = [48, 52, 55, 57, 58]
  @probs = @basic_blues = @notes.zip(a).inject({}){|m,v| m[v[0]] = v[1]; m}
  
  def note number
    Note.create(:channel => 2,
                :number => number,
                :duration => 0.25,
                :velocity => 100 + rand(27))
  end
  
  def drums
    @probs.map do |note_number, probs|
      @bar = (@bar + 1) % @mods.size
      Drum.new(:note => note(note_number + @mods[@bar]),
               :when => L{|beat| false},
               :number_generator => L{rand},
               :next => L{|queue| queue[rand(queue.size)]},
               :probabilities => probs)
    end
  end
  
  def randomize
    # @notes.each{|n| @probs[n] = (0...16).map{rand > 0.6 ? rand**3 : 0}}
    # @notes.each{|n| @probs[n] = (0...16).map{rand**10}}
    @notes.each{|n| @probs[n] = @basic_blues[n].zip((0...16).map{rand}).map{|a| a[0] == 1 ? 1 : a[1]**5}}
  end
  
  def play
    @bar = -1
    @loop = MyArkx.new(:clock => @clock, # rename Arkx to Loop
                       :measures => 1,
                       :logging => false,
                       :evil_timer_offset_wtf => 0.2,
                       :generator => MyRhythm.new(:drummaker => self))
    @loop.go
  end
  
  def stop
    # this seems wrong, somehow. really wrong.
    @loop = @loop.midi = nil
  end
  
  def probability_graph
    stack :width => 514, :height => 160, :bottom => 80, :left => 0 do
      dy = 0
      strokewidth 5
      cap :curve
      @probs.sort.each do |k, probs|
        stroke gray((k-46) / 14.0)
        dy += 10
        dx = 514.0 / probs.size
        lastx, lasty = 0, 100 + dy
        probs.each_with_index do |p, i|
          thisx, thisy = lastx + dx, 100 - p * 100 + dy
          line lastx, lasty, thisx, thisy
          lastx, lasty = thisx, thisy
        end
      end
    end
  end
  
  # randomize
  background 'mingus.jpg'
  @play = stack { button("Play", :top => 30, :left => 30) { play; @play.toggle; @stop.toggle } }
  @stop = stack { button("Stop", :top => 30, :left => 30) { stop; @stop.toggle; @play.toggle } }
  @stop.toggle
  @graph = probability_graph
  button("Random", :bottom => 30, :right => 30) { @graph.remove; randomize; @graph = probability_graph }
end