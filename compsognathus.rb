Shoes.setup do
  gem 'midiator'
end
require 'midiator'
require 'archaeopteryx/lib/archaeopteryx'
require 'templarx/templarx'

#
# widget for an audio-style knob
#

class Knob < Widget
  attr_accessor :value
  def initialize opts = {}
    @value = 0.5
    @radius = opts[:width] / 2
    @knob_radius = @radius * 0.8
    
    @knob = stack(:width => opts[:width], :height => opts[:height]) {
      # ticks
      stroke 'ddd'
      strokewidth 2
      (0..10).each do |i|
        radial_line i / 10.0, (@knob_radius..@radius*0.9)
      end
      
      # dial
      strokewidth 0
      fill '666'
      oval :left => @radius, :top => @radius, :center => true, :radius => @knob_radius
      fill '444'
      oval :left => @radius, :top => @radius, :center => true, :radius => @knob_radius*0.8

      # @value_box = edit_line(@value, :width => opts[:width], :height => 20, :left => 0, :top => 2 * @radius) {|e|
      #   @value = e.text.to_f
      #   draw_indicator
      # }
      @value_box = para((@value * 100).round, :stroke => white,
                                              :font => "Helvetica Neue Light 11px",
                                              :width => @radius * 2, :height => 11, :top => 8,
                                              :align => 'center')
      click { |button, x, y| knob_to x, y; @drag = true }
      motion { |x, y| knob_to x, y if @drag }
      release { |button, x, y| @drag = false }
    }
    draw_indicator
  end
  def knob_to x, y
    return if x > 2*@radius or y > 2*@radius
    x, y = x - @radius, @radius - y
    angle = Math.atan2(y, x)
    frac = ((-angle - 3 * Math::PI / 4) % (2*Math::PI)) / (3 * Math::PI / 2)
    return unless (0..1).include? frac
    self.value = frac
  end
  def radial_line frac, r
    angle = 3 * Math::PI * (frac + 0.5) / 2
    line (Math.cos(angle) * r.begin) + @radius, (Math.sin(angle) * r.begin) + @radius,
         (Math.cos(angle) * r.end) + @radius, (Math.sin(angle) * r.end) + @radius
  end
  def draw_indicator
    @line.remove if @line
    @knob.append do
      stroke '666'
      strokewidth 5
      @line = radial_line @value, (@knob_radius*0.8..@radius)
    end
  end
  def value= v
    @value = v
    @value_box.text = (v * 100).round
    draw_indicator
  end
end

#
# simple MIDI keyboard widget
#

class Keyboard < Widget
  attr_accessor :target
  def initialize opts = {}
    @width, @height = opts[:width], opts[:height]
    white_notes = [0, 2, 4, 5, 7, 9, 11]
    key_width = @width / 52.0
    last_x = -key_width
    white_keys = stack(:top => 0, :left => 0, :width => @width, :height => @height)
    black_keys = stack(:top => 0, :left => 0, :width => @width, :height => @height)
    stroke black
    flow(:width => @width, :height => @height) {
      (21..109).each do |number|
        scale_note = number % 12
        if white_notes.include? scale_note
          last_x += key_width
          x, y, w, h, c, s = last_x.to_i, 0, key_width.to_i, @height, white, white_keys
          line last_x.to_i, 0, last_x.to_i, @height
        else
          x, y, w, h, c, s = (last_x + key_width * 2 / 3).to_i, 0,
                             (key_width * 2 / 3).to_i, @height * 2 / 3,
                             black, black_keys
        end
        s.append { midi_button({:left => x, :top => y, :width => w, :height => h}, c, number) }
      end
    }
    @midi = MIDIator::Interface.new
    @midi.autodetect_driver
  end
  def play_note number
    @midi.play(number, 0.1, 2, 100)
  end
  def midi_button(r, c, n)
    stack(r) { background c; click {|button, x, y| play_note(n); target.call(n) if target} }
  end
end

#
# Monkeypatching me some arkx
#
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

class Drummer
  $clock = Clock.new(170)
  $mutation = L{|measure| 0 == (measure - 1) % 2}
  $measures = 4
  
  attr_accessor :probabilities
  
  def read drumdef
    instance_eval drumdef + "\n@probabilities = probabilities"
  end
  def note number
    Note.create(:channel => 2,
                :number => number,
                :duration => 0.25,
                :velocity => 100 + rand(27))
  end
  def drums
    @probabilities.map do |note_number, probs|
      Drum.new(:note => note(note_number),
               :when => L{|beat| false},
               :number_generator => L{rand},
               :next => L{|queue| queue[rand(queue.size)]},
               :probabilities => probs)
    end
  end
end

Shoes.app(:title => 'Compsognathus', :width => 840, :height => 600) {
  # loading and saving
  def load_file
    return unless @path = ask_open_file
    @filename.text = File.basename @path
    @drummer.read(File.open(@path, 'r').read)
    
    # remove old controls
    @controls.each {|c| c[:line].remove}
    @controls = []
    @drummer.probabilities.size.times { add_line }
    
    @drummer.probabilities.sort.each_with_index {|p, i|
      note, probs = p[0], p[1]
      @controls[i][:label].text = note
      @controls[i][:beats].each_with_index{|b, k| b.value = probs[k]}
    }
  end
  def save_file
    unless @path
      return unless @path = ask_save_file # doesn't work, on OSX anyway. yarr
      @filename.text = File.basename @path
    end
    t = Templarx.new :definition_path => @path, :probabilities => probabilities
    t.rewrite_drum_definition
  end
  
  # drumming
  def probabilities
    probs = {}
    @controls.each do |c|
      probs[c[:label].text.to_i] = c[:beats].map{|b| b.value}
    end
    probs
  end
  def drums
    @drummer.probabilities = probabilities
    @drummer.drums
  end
  def play
    @loop = MyArkx.new(:clock => $clock, # rename Arkx to Loop
                       :measures => $measures,
                       :logging => false,
                       :evil_timer_offset_wtf => 0.2,
                       :generator => MyRhythm.new(:drummaker => self))
    @loop.go
  end
  def stop
    # this seems wrong, somehow. really wrong.
    @loop = @loop.midi = nil
  end
  
  # one line of drum knobs looks something like this
  def add_line
    @control_stack.append do
      control = {}
      control[:line] = flow(:margin => 5) {
        stack(:width => 60) {
          control[:label] = subtitle(rand(87)+21, :font => 'Helvetica Neue Light 30px',
                                                  :stroke => white,
                                                  :align => 'right')
          click { |button, x, y|
            window(:title => 'Keyboard', :width => 600, :height => 90, :resizable => false) {
              keyboard(:width => 600, :height => 90).target = L{|num| control[:label].text = num}
            }
          }
        }
        control[:beats] = (0...16).map { |beat|
          subtitle ' ' if beat % 4 == 0
          knob(:width => 40, :height => 40)
        }
      }
      @controls << control
    end
  end
  
  # heeeere's the app
  background '222'..'111'
  background 'compy.png'
  stroke white
  flow {
    banner "Compsognathus", :stroke => white, :font => 'Helvetica Neue Light', :margin => 10
    flow(:top => 30, :margin => 10) {
      @play = stack { button("Play!") { play; @play.toggle; @stop.toggle } }
      @stop = stack { button("Stop!") { stop; @stop.toggle; @play.toggle } }
      @stop.toggle
    }
  }
  @controls = []
  @control_stack = stack { }
  add_line
  flow(:margin => 10) {
    button("Add drum") { add_line }
    button("Load") { load_file }
    button("Save") { save_file }
    @filename = para :stroke => white, :font => 'Helvetica Neue Light'
  }
  
  @drummer = Drummer.new
}
