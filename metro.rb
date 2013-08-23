###############################################################################
### CMSC330 Project: Multi-threaded Train Simulation                        ###
### Source code: metro.rb                                                   ###
### Description: A multi-threaded Ruby program that simulates               ###
###              the Washington Metro by creating Train and Person threads  ###
###############################################################################

# Student: Alexander Bezobchuk

require "monitor"
Thread.abort_on_exception = true   # to avoid hiding errors in threads 

#----------------------------------------------------------------
# Metro Simulator
#----------------------------------------------------------------

def simulate(lines,numTrains,passengers,simMonitor)

    # puts lines.inspect
    # puts numTrains.inspect
    # puts passengers.inspect
    # simMonitor.inspect
    # sleep(0.1.)

    thread_pass_hash = { }
    thread_train_hash = { }

    @stations = { }
    @trains = { }
    @my_conditions = { }

    @simMonitor = simMonitor
    @lines = lines
    @numTrains = numTrains
    @passengers = passengers

    # Set up a data structure containing all the conditionals for each monitor
    @simMonitor.keys.each do |line|

        @my_conditions[line] = { }

        @lines[line].each do |station|
            if (@my_conditions[line][station] == nil)
                @my_conditions[line][station] = { }
            end
            @my_conditions[line][station]["Train"] = @simMonitor[line].new_cond
            if (@my_conditions[line][station]["Passenger"] == nil)
                @my_conditions[line][station]["Passenger"] = { }
            end
            (1..@numTrains[line]).each do |num|
                @my_conditions[line][station]["Passenger"][num.to_s] = @simMonitor[line].new_cond
            end
        end

    end

    # Set up the various data structures that will assist the threads
    lines.each do |line_v, stations_v|
        stations_v.each do |station_v|
            if (@stations[station_v] == nil)
                @stations[station_v] = { }
            end
            @stations[station_v][line_v] = { }
            @stations[station_v]["passenger"] = { } 
        end
    end

    passengers.each do |name, itinerary|
        @stations[itinerary[0]]["passenger"][name] = 0 
    end

    def sim_aux_train(train_line, train_num)

        stations_list = @lines[train_line]

        begin

            # Round trip from first station to last
            stations_list.each do |station|
                @simMonitor[train_line].synchronize {
                    @my_conditions[train_line][station]["Train"].wait_until { @stations[station][train_line].empty? }
                    puts "Train #{train_line} #{train_num} entering #{station}"
                    $stdout.flush
                    @stations[station][train_line][train_num] = 0
                    @my_conditions[train_line][station]["Passenger"][train_num].broadcast # Wake up passengers while entering station
                }
                sleep(0.1) # Sleep before leaving station
                @simMonitor[train_line].synchronize {
                    puts "Train #{train_line} #{train_num} leaving #{station}"
                    $stdout.flush
                    @stations[station][train_line].delete(train_num)
                    @my_conditions[train_line][station]["Train"].broadcast # Wake up trains while exiting station
                }
            end

            # Round trip from last station to first
            rev_stations_list = nil
            if (@passengers.empty?)
                rev_stations_list = (stations_list.reverse).slice(1,stations_list.length - 1)
            else
                rev_stations_list = (stations_list.reverse).slice(1,stations_list.length - 2)
            end
            rev_stations_list.each do |station|
                @simMonitor[train_line].synchronize {
                    @my_conditions[train_line][station]["Train"].wait_until { @stations[station][train_line].empty? }
                    puts "Train #{train_line} #{train_num} entering #{station}"
                    $stdout.flush
                    @stations[station][train_line][train_num] = 0
                    @my_conditions[train_line][station]["Passenger"][train_num].broadcast # Wake up passengers while entering station
                }
                sleep(0.1) # Sleep before leaving station
                @simMonitor[train_line].synchronize {
                    puts "Train #{train_line} #{train_num} leaving #{station}"
                    $stdout.flush
                    @stations[station][train_line].delete(train_num)
                    @my_conditions[train_line][station]["Train"].broadcast # Wake up trains while exiting station
                }
            end
        end while (!@passengers.empty?)
    end

    def sim_aux_pass(pass_name, pass_itinerary)

        pass_itinerary.enum_cons(2).select do |curr_station, next_station|

            line_to_take = nil

            # Search for a line that contains both stations 'curr_station' & 'next_station'
            @lines.each do |line, station_list|
                if (station_list.include?(curr_station) && station_list.include?(next_station))
                    line_to_take = line
                end
            end

            if (line_to_take != nil)

                # Pick a random train number in the line to create a more non-deterministic result =D
                train_num = ((1..@numTrains[line_to_take]).to_a.shuffle.first).to_s 

                # Let passenger board train when the specified train arrives
                @simMonitor[line_to_take].synchronize {
                    @my_conditions[line_to_take][curr_station]["Passenger"][train_num].wait_while { @stations[curr_station][line_to_take][train_num] == nil }
                    puts "#{pass_name} boarding train #{line_to_take} #{train_num} at #{curr_station}"
                    $stdout.flush
                }
                # Let passenger leave train when specified train arrives
                @simMonitor[line_to_take].synchronize {
                    @my_conditions[line_to_take][next_station]["Passenger"][train_num].wait_until { @stations[next_station][line_to_take][train_num] != nil }
                    puts "#{pass_name} leaving train #{line_to_take} #{train_num} at #{next_station}"
                    $stdout.flush
                }
            else
                puts "Error: could not find metro line for station: #{next_station}; passenger: #{pass_name}????"
                $stdout.flush
            end

        end

    end

    # Create the train threads
    numTrains.each do |line, num|
        (1..num).each do |train_num| 
            thread_train_hash[line + " #{train_num}"] = Thread.new { sim_aux_train(line, "#{train_num}") }
        end
    end

    # Create the passenger threads
    passengers.each do |name, itinerary|
        thread_pass_hash[name] = Thread.new { sim_aux_pass(name, itinerary) }
    end

    # Join the threads. If there are no passengers, wait till each train does a round trip.
    # Otherwise, wait till each passenger completes his/her itinerary
    if (!@passengers.empty?)
        thread_pass_hash.keys.each do |passenger|
            thread_pass_hash[passenger].join
        end
    else
        thread_train_hash.keys.each do |train|
            thread_train_hash[train].join
        end
    end
    # There are m (each train) + n (each passenger) + 1 (main) threads
end

#----------------------------------------------------------------
# Simulation Display
#----------------------------------------------------------------

# line = hash of line names to array of stops
# stations = hash of station names =>
#                  hashes for each line => hash of trains at station
#               OR hash for "passenger" => hash of passengers at station
# trains = hash of train names =>  hash of passengers

def displayState(lines,stations,trains)
    lines.keys.sort.each { |color|
        stops = lines[color]
        puts color
        stops.each { |stop| 
            pStr = ""
            tStr = ""

            stations[stop]["passenger"].keys.sort.each { |passenger|
                pStr << passenger << " "
            }

            stations[stop][color].keys.sort.each { |trainNum| 
                tr = color+" "+trainNum
                tStr << "[" << tr
                if trains[tr] != nil
                    trains[tr].keys.sort.each { |p|
                        tStr << " " << p
                    }
                end
                tStr << "]"
            }

            printf("  %25s %10s %-10s\n", stop, pStr, tStr)
        }	
    }
    puts 
end

def display(lines,passengers,output)

    # puts lines.inspect
    # puts passengers.inspect
    # puts output.inspect

    stations = {}
    trains = {}

    # initial display of simulation
    lines.each do |line_v, stations_v|
        stations_v.each do |station_v|
            if (stations[station_v] == nil) 
                stations[station_v] = { }
            end
            stations[station_v][line_v] = { }
            stations[station_v]["passenger"] = { } 
        end
    end

    passengers.each do |name, itinerary|
        stations[itinerary[0]]["passenger"][name] = 0 
    end

    displayState(lines,stations,trains)

    output.each {|o|
        puts o

        o =~ /^(Train|\w+)/
        if $1 == "Train"

            # info[0] = train Line
            # info[1] = train number
            # info[2] = entering or leaving
            # info[3] = station name
            info = o.scan(/^Train\s(\w+)\s(\d)\s(entering|leaving)\s(.+$)/)
            info = info[0]

            if info[2] == "entering"
                # The train enters the station
                stations[info[3]][info[0]][info[1]] = 0
            else
                # The train leaves the station
                stations[info[3]][info[0]].delete(info[1])
            end
        else
            # info[0] = Passanger name
            # info[1] = boarding or leaving
            # info[2] = train line 
            # info[3] = train number
            # info[4] = station name
            info = o.scan(/(^\w+)\s(boarding|leaving)\strain\s(\w+)\s(\d)\sat\s(.+$)/)
            info = info[0]

            if info[1] == "boarding"
                # The passanger leaves the station and boards the train
                if trains[info[2] + " " + info[3]] == nil
                    trains[info[2] + " " + info[3]] = { }
                    trains[info[2] + " " + info[3]][info[0]] = 0
                    stations[info[4]]["passenger"].delete(info[0])
                else
                    trains[info[2] + " " + info[3]][info[0]] = 0
                    stations[info[4]]["passenger"].delete(info[0])
                end
            else
                # The passanger leaves the train and boards the station
                trains[info[2] + " " + info[3]].delete(info[0])
                stations[info[4]]["passenger"][info[0]] = 0
            end
        end

        displayState(lines,stations,trains)
    }
end

#----------------------------------------------------------------
# Simulation Verifier
#----------------------------------------------------------------

def verify(lines,numTrains,passengers,output)

    # puts lines.inspect
    # puts numTrains.inspect
    # puts passengers.inspect
    # puts output.inspect

    parts = { }
    (1..8).each do |x|
        parts[x] = true 
    end

    #----------- Check that each train starts at it's respective initial station -------
    check_initial = { }
    output.each do |o|

        o =~ /^(Train|\w+)/

        if $1 == "Train"
            info = o.scan(/^Train\s(\w+)\s(\d)\s(entering|leaving)\s(.+$)/)
            info = info[0]

            if check_initial[info[0] + " " + info[1]] == nil
                check_initial[info[0] + " " + info[1]] = info[3]
            end
        end
    end

    lines.each do |line, stations_list|
        numTrains.each do |line_t, num_t|
            (1..num_t).each do |num|
                if check_initial[line + " " + num.to_s()] != stations_list[0]
                    parts[1] = false
                end
            end
        end 
    end

    #-------------- Check that trains enters station before leaving it -----------------
    check_path = { }
    output.each do |o|

        o =~ /^(Train|\w+)/
        if $1 == "Train"
            info = o.scan(/^Train\s(\w+)\s(\d)\s(entering|leaving)\s(.+$)/)
            info = info[0]

            if check_path[info[0] + " " + info[1]] == nil
                check_path[info[0] + " " + info[1]] = [ ]
            end
            check_path[info[0] + " " + info[1]].push(info[2] + " " + info[3])
        end
    end

    check_path.each do |train, stations_visited|
        stations_visited.each_slice(2) do |curr_station, next_station|

            if (next_station != nil)
                curr_station =~ /(^entering|leaving)\s(.+$)/
                act_1 = $1
                stat_1 = $2
                next_station =~ /(^entering|leaving)\s(.+$)/
                act_2 = $1
                stat_2 = $2

                if (act_1 != "entering" || act_2 != "leaving" || stat_1 != stat_2) 
                    parts[2] = false
                end
            end
        end
    end

    #----------------- Check two trains from same line not at same station -------------
    check_station_trains = { }

    output.each do |o|
        o =~ /^(Train|\w+)/

        if $1 == "Train"
            # info[0] = train Line
            # info[1] = train number
            # info[2] = entering or leaving
            # info[3] = station name
            info = o.scan(/^Train\s(\w+)\s(\d)\s(entering|leaving)\s(.+$)/)
            info = info[0]

            if info[2] == "entering"
                if check_station_trains[info[3]] == nil
                    check_station_trains[info[3]] = [ ]
                end

                if check_station_trains[info[3]].include?(info[0])
                    parts[3] = false
                else
                    check_station_trains[info[3]].push(info[0])
                end
            else
                check_station_trains[info[3]].delete(info[0])
            end
        end

    end

    #---------- Check that all passengers reach their final destinations ---------------
    check_pass = { }

    passengers.each do |name, itinerary|
        final_stop = itinerary[itinerary.length - 1] 
        output.each do |o|
            o =~ /^(Train|\w+)/
            if $1 != "Train"
                info = o.scan(/(^\w+)\s(boarding|leaving)\strain\s(\w+)\s(\d)\sat\s(.+$)/)
                info = info[0]
                name_t = info[0]
                if (name == name_t && info[4] == final_stop)
                    check_pass[name] = true 
                end
            end
        end
    end

    if check_pass.values.include?(false) || check_pass.length != passengers.length
        parts[4] = false
    end

    #---------- If no passengers, check trains for round trips -------------------------
    if (passengers.empty?)
        check_train_trip = { }

        output.each do |o|
            o =~ /^(Train|\w+)/

            if $1 == "Train"
                info = o.scan(/^Train\s(\w+)\s(\d)\s(entering|leaving)\s(.+$)/)
                info = info[0]

                if (check_train_trip[info[0] + " " + info[1]] == nil)
                    check_train_trip[info[0] + " " + info[1]] = [ ]
                end
                check_train_trip[info[0] + " " + info[1]].push(info[3])
            end
        end

        check_train_trip.each do |train, stations_list|

            s_l = [ ]
            (lines[(train.split(" "))[0]]).each do |station|
                s_l.push(station)
                s_l.push(station)
            end

            s_l = s_l + ((s_l.reverse).slice(2, s_l.length - 1))

            if (s_l != stations_list.flatten)
                parts[5] = false
            end

        end
    end

    #-------------- Check that passengers board/leave when train is available --------------
    boarded_trains = { }


    output.each do |o|
        o =~ /^(Train|\w+)/

        if $1 == "Train"
            # info[0] = train Line
            # info[1] = train number
            # info[2] = entering or leaving
            # info[3] = station name
            info = o.scan(/^Train\s(\w+)\s(\d)\s(entering|leaving)\s(.+$)/)
            info = info[0]

            if info[2] == "entering"
                if boarded_trains[info[3]] == nil
                    boarded_trains[info[3]] = [ ] 
                end
                boarded_trains[info[3]].push(info[0] + " " + info[1])
            else
                boarded_trains[info[3]].delete(info[0] + " " + info[1])
            end 
        else
            # info[0] = Passanger name
            # info[1] = boarding or leaving
            # info[2] = train line 
            # info[3] = train number
            # info[4] = station name
            info = o.scan(/(^\w+)\s(boarding|leaving)\strain\s(\w+)\s(\d)\sat\s(.+$)/)
            info = info[0]

            if !boarded_trains[info[4]].include?(info[2] + " " + info[3])
                parts[6] = false
            end

        end
    end

    #-------------- Check if a train enters a station before it leaves it ---------------
    arrived_trains = { }
    departed_trains = { }

    output.each do |o|
        o =~ /^(Train|\w+)/

        if $1 == "Train"
            # info[0] = train Line
            # info[1] = train number
            # info[2] = entering or leaving
            # info[3] = station name
            info = o.scan(/^Train\s(\w+)\s(\d)\s(entering|leaving)\s(.+$)/)
            info = info[0]

            if info[2] == "entering"
                if arrived_trains[info[0] + " " + info[1]] == nil
                    arrived_trains[info[0] + " " + info[1]] = [ ]
                end
                arrived_trains[info[0] + " " + info[1]].push(info[3])
            else
                if !arrived_trains[info[0] + " " + info[1]].include?(info[3])
                    parts[7] = false
                end
                arrived_trains[info[0] + " " + info[1]].delete(info[3])
            end
        end
    end

    #-------------- Check to see if train moves forward and backward along line ---------
    check_train_paths = { }

    output.each do |o|
        o =~ /^(Train|\w+)/

        if $1 == "Train"
            # info[0] = train Line
            # info[1] = train number
            # info[2] = entering or leaving
            # info[3] = station name
            info = o.scan(/^Train\s(\w+)\s(\d)\s(entering|leaving)\s(.+$)/)
            info = info[0]

            if info[2] == "entering"
                if check_train_paths[info[0] + " " + info[1]] == nil
                    check_train_paths[info[0] + " " + info[1]] = [ ]
                end
                check_train_paths[info[0] + " " + info[1]].push(info[3])
            end
        end
    end
    check_train_paths.each do |train, stations_list|
        train_line = (train.split(" "))[0]
        i = 0
        stations = lines[train_line]
        station_count = stations.length
        s_t = stations

        while i < (stations_list.length/s_t.length) + 1 do 
            s_t = s_t.reverse
            stations = stations + s_t.slice(1, stations.length - 1)
            i += 1
        end

        i = 0

        stations_list.each do |station|
            if station != stations[i]
                parts[8] = false
            end
            i += 1 
        end

    end

    #-------------------------- CHECK ALL PARTS -------------------------------
    if parts.values.include?(false)
        false
    else
        true
    end

end
