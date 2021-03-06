class LocsPlus
  include Purugin::Plugin, Purugin::Colors, Purugin::Tasks
  description 'LocsPlus', 0.5
  
  module CoordinateEncoding
    def encode(value)
      (value.to_i + 32000).to_s(36)
    end
  
    def decode(value)
      value.to_i(36) - 32000
    end
  end
  
  include CoordinateEncoding
  
  def dirify(value, positive, negative)
    value < 0 ? [value.abs, negative] : [value, positive]
  end  

  def loc_string(name, player, x, y, z, pitch, yaw)
    distance = distance_from_loc(player, x, y, z)
    l = player.location
    x1, z1, y1 = l.getX - x, l.getZ - z, l.getY - y
    x1, ns = dirify(x1, 'N', 'S')
    z1, ew = dirify(z1, 'E', 'W')
    y1, ud = dirify(y1, 'D', 'U')
    pos = pos_string(x, y, z)
    format("%s %s ~%0.1f voxs [%0.1f%s, %0.1f%s, %0.1f%s]", name, pos,
           distance, x1, green(ns), z1, green(ew), y1, green(ud))
  end

  def pos_string(x, y, z, *)
    format("%0.1f, %0.1f, %0.1f [%s, %s, %s]", x, y, z,
      encode(x), encode(y), encode(z))
  end

  def direction(location)
    case location.yaw.abs
    when 0..22.5 then "W"
    when 22.5..67.5 then "NW"
    when 67.5..112.5 then "N"
    when 112.5..157.5 then "NE"
    when 157.5..202.5 then "E"
    when 202.5..247.5 then "SE"
    when 247.5..292.5 then "S"
    when 292.5..337.5 then "SW"
    when 337.5..360 then "W"
    end
  end

  def distance_from_loc(player, x, y, z)
    l = player.location
    Math.sqrt((l.getX-x)*(l.getX-x)+(l.getY-y)*(l.getY-y)+(l.getZ-z)*(l.getZ-z))
  end

  def locations(player)
    @locs ||= {}
    @locs[player.name] = {} unless @locs[player.name]
    @locs[player.name]
  end

  def location(player, name)
    return player.world.spawn_location if name == 'bind'

    player_locs = locations(player)
    raise ArgumentError.new "No player stored locations" unless player_locs

    loc = player_locs[name]
    raise ArgumentError.new "Invalid location #{name}" unless loc

    org.bukkit.Location.from_a loc
  end

  def locations_path
    @path ||= File.join getDataFolder, 'locations.data'
  end

  def load_locations
    return {} unless File.exist? locations_path
    File.open(locations_path, 'rb') { |io| @locs = Marshal.load io }
  end

  def save_locations
    File.open(locations_path, 'wb') { |io| Marshal.dump @locs, io }
  end

  def setup_tracker_thread
    tracks = @tracks = {} # All tracking locations for all players
    @track_time = config.get_fixnum!('locs_plus.track_time', 4)

    # Tracker thread to display all players locs of interest
    sync_task(0, @track_time) do
      tracks.each do |player, (name, loc)|
        player.msg loc_string(name, player, *loc)
      end
    end
  end

  def waypoint_create(player, name)
    raise ArgumentError.new "Cannot use 'bind' as name" if name == 'bind'
    locations(player)[name] = player.location.to_a
    save_locations
  end

  def waypoint_help(p)
    p.send_message "/waypoint - show all waypoints"
    p.send_message "/waypoint name|bind - show named waypoint"
    p.send_message "/waypoint create name - create waypoint for name"
    p.send_message "/waypoint remove name - remove waypoint for name"
    p.send_message "/waypoint help - display help for waypoints"
  end

  def waypoint_remove(player, name)
    locations(player).delete(name)
    save_locations
  end

  def waypoint_show(player, name)
    player.send_message loc_string(name, player, *location(player, name))
  end

  def waypoint_show_all(player)
    player.msg "Saved waypoints (name loc):"
    locations(player).each do |name, loc|
      player.send_message loc_string(name, player, *loc)
    end
    player.send_message loc_string("bind", player, *player.world.spawn_location.to_a)
  end

  def waypoint(sender, *args)
    case args.length
    when 0 then waypoint_show_all sender
    when 1 then 
      if args[0] == 'help'
        waypoint_help sender
      else
        waypoint_show sender, args[0]
      end
    when 2 then
      command, arg = *args

      if command == 'create'
        waypoint_create sender, arg
      elsif command == 'remove'
        waypoint_remove sender, arg
      else
        sender.msg red("Bad args: /waypoint #{args.join(' ')}")
      end
    else
      sender.msg red("Bad args: /waypoint: #{args.join(' ')}")
    end
  rescue ArgumentError => error
    sender.msg red("Error: #{error.message}")
  end

  def track(sender, *args)
    case args.length
    when 1 then
      name = args[0]
      if name  == 'stop'
        @tracks[sender] = nil
        sender.msg "Tracking stopped"
      elsif name == 'help'
        track_help sender
      else
        begin
          loc = location sender, name
          if loc
            @tracks[sender] = [name, loc] 
          else
            sender.msg "No location? for #{name}"
          end
        rescue ArgumentError => error
          sender.msg red(error.message)
        end
      end
    end
  end

  def track_help(player)
    player.msg "/track name {time} - update loc every n seconds"
    player.msg "/track stop"
  end

  def on_enable
    load_locations
    public_player_command('loc', 'display current location') do |me, *|
      l = me.location
      me.msg "Location: #{pos_string(*l.to_a)} #{direction(l)}"
    end

    public_player_command('waypoint', 'manage waypoints', '/waypoint name|create|remove|help? name?') do |me, *args|
      waypoint me, *args
    end

    setup_tracker_thread
    public_player_command('track', 'track to a waypoint', '/track {waypoint_name|stop}') do |sender, *args|
      track sender, *args
    end
  end
end
