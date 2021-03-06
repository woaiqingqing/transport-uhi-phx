#############################################################################
## DATA IMPORT SCRIPT FOR 2017 PHOENIX, AZ WEATHER DATA - VARIOUS SOURCES ##
###########################################################################
t.start <- Sys.time() # start script timestamp

# list of all dependant packages
list.of.packages <- c("httr",
                      "jsonlite",
                      "lubridate",
                      "weathermetrics",
                      "data.table",
                      "rnoaa",
                      "here")

# install missing packages
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages)

# load packages
invisible(lapply(list.of.packages, library, character.only = TRUE))


#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
# Import Arizona Meteorological Network data  #
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

encanto <- rbindlist(lapply(list.files(here(path = "data/weather data/AZMET/Encanto/raw"), pattern="txt$", full.names= T), read.csv, header = F))
desert.ridge <- rbindlist(lapply(list.files(here(path = "data/weather data/AZMET/Desert Ridge/raw"), pattern="txt$", full.names= T), read.csv, header = F))
mesa <- rbindlist(lapply(list.files(here(path = "data/weather data/AZMET/Mesa/raw"), pattern="txt$", full.names= T), read.csv, header = F))
greenway <- rbindlist(lapply(list.files(here(path = "data/weather data/AZMET/Greenway/raw"), pattern="txt$", full.names= T), read.csv, header = F))

# add station ID to each dataset
encanto$station <- "Encanto"
desert.ridge$station <- "Desert Ridge"
mesa$station <- "Mesa"
greenway$station <- "Greenway"

# bind all together, remove individual dfs
azmet.data <- rbind(encanto,desert.ridge,mesa,greenway)

# clean up space
rm(encanto,desert.ridge,mesa,greenway)
gc()

# assign column names (see data dictionary)
colnames(azmet.data) <- c("year","day.year","hour","temp.c","rh","vap","sol","precip","soil.4.in","soil.20.in","winspd","wind.mag","windir","wind.dir.dev","max.wind.spd","ETo","act.vap","dewpt.c","station.name")

# fix temp = 999 to NA
azmet.data$temp.c <- ifelse(azmet.data$temp.c == 999, NA, azmet.data$temp.c)

# create fahrenheit temp/dew
azmet.data[, temp.f := ((temp.c * 1.8) + 32)]
azmet.data[, dewpt.f := ((dewpt.c * 1.8) + 32)]

# add date column
azmet.data$date <- as.Date(azmet.data$day.year-1, origin = paste0(azmet.data$year,"-01-01"))

# format date + time in new column as YYYY-MM-DD HH:MM:SS
azmet.data$date.time  <- ymd_hm(paste0(azmet.data$date," ",azmet.data$hour,":00"), tz = "US/Arizona")

# read AZMET station data
azmet.stations <- fread(here("data/weather data/AZMET/stations.csv"))

# add data source column and id column (NA, but for ordered cols later)
azmet.data$source <- "AZMET"
azmet.stations$source <- "AZMET"
azmet.data$id <- NA
azmet.stations$id <- NA

# convert elevation to feet from meters
azmet.stations[, elevation := elevation * 3.28084]

# keep relevant columns only
azmet.data <- azmet.data[,c("source","station.name","date.time","temp.f","dewpt.f","temp.c","dewpt.c","winspd","windir")]
azmet.stations <- azmet.stations[,c("source","station.name","lat","lon","elevation","id")]

# keep 2017 data only
azmet.data <- azmet.data[year(date.time) == 2017]


#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#
# Import National Centers for Environmental Information data  #
#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#

ncei.data <- read_fwf(here("data/weather data/NCEI/2016_data.txt"), skip = 1,
                       fwf_empty(here("data/weather data/NCEI/2016_data.txt"),
                                 col_names = c("id","WBAN","date","windir","winspd","GUS","CLG","SKC","L","M","H","VSB","MW1","MW2","MW3","MW4","AW1","AW2","AW3","AW4","W","temp.f","dewpt.f","SLP","ALT","STP","MAX","MIN","PCP01","PCP06","PCP24","PCPXX","SD")))

ncei.stations <- read_fwf(here(path = "data/weather data/NCEI/stations.txt"), skip = 2, fwf_widths(c(7,6,31,51,31,9,9,10), c("id","WBAN","station.name","COUNTRY","STATE","lat","lon","elevation")))

# set as data.table
setDT(ncei.data)
setDT(ncei.stations)

# convert variables to numeric (via characters because "NA" is "**")
ncei.data[, temp.f := as.numeric(as.character(temp.f))]
ncei.data[, dewpt.f := as.numeric(as.character(dewpt.f))]
ncei.data[, winspd := as.numeric(as.character(winspd))]
ncei.data[, windir := as.numeric(as.character(windir))]

# create celcius temp/dew
ncei.data[, temp.c := ((temp.f - 32) / 1.8)]
ncei.data[, dewpt.c := ((dewpt.f - 32) / 1.8)]

# format date + time in new column as YYYY-MM-DD HH:MM:SS
ncei.data$date.time  <- ymd_hm(ncei.data$date, tz = "UTC")

# convert to AZ timezone
ncei.data$date.time <- with_tz(ncei.data$date.time, tz = "US/Arizona") # change timezone to local (AZ)

# merge station.name to data
ncei.data <- merge(ncei.data, ncei.stations[,.(station.name,id)], by = "id")

# add data source column
ncei.data$source <- "NCEI"
ncei.stations$source <- "NCEI"

# convert elevation to feet from meters
ncei.stations[, elevation := elevation * 3.28084]

# keep relevant columns only
ncei.data <- ncei.data[,c("source","station.name","date.time","temp.f","dewpt.f","temp.c","dewpt.c","winspd","windir")]
ncei.stations <- ncei.stations[,c("source","station.name","lat","lon","elevation","id")]

# keep 2017 data only
ncei.data <- ncei.data[year(date.time) == 2017]


#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#
# Import Maricopa County Flood Control District data  #
#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#

# temp data
temp.files <- list.files(here(path = "data/weather data/MCFCD/2017/Temp"), pattern="txt$", full.names = T) # full file path names
temp.names <- gsub(".txt", "", list.files(here(path = "data/weather data/MCFCD/2017/Temp"), pattern = "txt$", full.names = F)) # names (stations) of files
mcfcd.temp.data <- rbindlist(lapply(temp.files, fread), idcol = "id") # load all station data 
mcfcd.temp.data[, id := factor(id, labels = basename(temp.names))] # add station names to column 'station'
mcfcd.temp.data[, id := as.character(id)] # convert to character for matching
colnames(mcfcd.temp.data) <- c("id","date","time","temp.f") # add rest of column names
mcfcd.temp.data$date.time  <- mdy_hms(paste0(mcfcd.temp.data$date," ",mcfcd.temp.data$time), tz = "US/Arizona") # MCFCD data is all local

# dewpt data
dewpt.files <- list.files(here(path = "data/weather data/MCFCD/2017/Dewpoint"), pattern="txt$", full.names = T) # full file path names
dewpt.names <- gsub(".txt", "", list.files(here(path = "data/weather data/MCFCD/2017/Dewpoint"), pattern = "txt$", full.names = F)) # names (stations) of files
mcfcd.dewpt.data <- rbindlist(lapply(dewpt.files, fread), idcol = "id") # load all station data 
mcfcd.dewpt.data[, id := factor(id, labels = basename(dewpt.names))] # add station names to column 'station'
mcfcd.dewpt.data[, id := as.character(id)] # convert to character for matching
colnames(mcfcd.dewpt.data) <- c("id","date","time","dewpt.f") # add rest of column names
mcfcd.dewpt.data$date.time  <- mdy_hms(paste0(mcfcd.dewpt.data$date," ",mcfcd.dewpt.data$time), tz = "US/Arizona") # MCFCD data is all local

# windir data
windir.files <- list.files(here(path = "data/weather data/MCFCD/2017/Wdir"), pattern="txt$", full.names = T) # full file path names
windir.names <- gsub(".txt", "", list.files(here(path = "data/weather data/MCFCD/2017/Wdir"), pattern = "txt$", full.names = F)) # names (stations) of files
mcfcd.windir.data <- rbindlist(lapply(windir.files, fread), idcol = "id") # load all station data 
mcfcd.windir.data[, id := factor(id, labels = basename(windir.names))] # add station names to column 'station'
mcfcd.windir.data[, id := as.character(id)] # convert to character for matching
colnames(mcfcd.windir.data) <- c("id","date","time","windir") # add rest of column names
mcfcd.windir.data$date.time  <- mdy_hms(paste0(mcfcd.windir.data$date," ",mcfcd.windir.data$time), tz = "US/Arizona") # MCFCD data is all local

# winspd data
winspd.files <- list.files(here(path = "data/weather data/MCFCD/2017/Wspd"), pattern="txt$", full.names = T) # full file path names
winspd.names <- gsub(".txt", "", list.files(here(path = "data/weather data/MCFCD/2017/Wspd"), pattern = "txt$", full.names = F)) # names (stations) of files
mcfcd.winspd.data <- rbindlist(lapply(winspd.files, fread), idcol = "id") # load all station data 
mcfcd.winspd.data[, id := factor(id, labels = basename(winspd.names))] # add station names to column 'station'
mcfcd.winspd.data[, id := as.character(id)] # convert to character for matching
colnames(mcfcd.winspd.data) <- c("id","date","time","winspd") # add rest of column names
mcfcd.winspd.data$date.time  <- mdy_hms(paste0(mcfcd.winspd.data$date," ",mcfcd.winspd.data$time), tz = "US/Arizona") # MCFCD data is all local

# solar data
solar.files <- list.files(here(path = "data/weather data/MCFCD/2017/Solar"), pattern="txt$", full.names = T) # full file path names
solar.names <- gsub(".txt", "", list.files(here(path = "data/weather data/MCFCD/2017/Solar"), pattern = "txt$", full.names = F)) # names (stations) of files
mcfcd.solar.data <- rbindlist(lapply(solar.files, fread), idcol = "id") # load all station data 
mcfcd.solar.data[, id := factor(id, labels = basename(solar.names))] # add station names to column 'station'
mcfcd.solar.data[, id := as.character(id)] # convert to character for matching
colnames(mcfcd.solar.data) <- c("id","date","time","solar") # add rest of column names
mcfcd.solar.data$date.time  <- mdy_hms(paste0(mcfcd.solar.data$date," ",mcfcd.solar.data$time), tz = "US/Arizona") # MCFCD data is all local

# station data
mcfcd.stations <- fread(here("data/weather data/MCFCD/stations.csv")) # load station data
mcfcd.stations <- mcfcd.stations[!is.na(id)]  # remove stations without an ID
mcfcd.stations[, id := as.character(id)] # convert id to character for matching

# function to convert degree min sec lat lon to decimal
dms2dec <- function(x){ 
  z <- sapply(strsplit(x, " "), as.numeric)
  z[1, ] + z[2, ]/60 + z[3, ]/3600
}

# b/c the dms lat lon had one decimal place after the seconds (DD:MM:SS.S), we assume corresponding accuarcy of XX.XXX in decimal lat lon (3 digits to rhs)
mcfcd.stations$lat <- round(dms2dec(mcfcd.stations$lat.dms), digits = 3) # convert station deg-min-sec to decimal lat
mcfcd.stations$lon <- round(dms2dec(mcfcd.stations$lon.dms), digits = 3) # convert station deg-min-sec to decimal lon
mcfcd.stations$lon <- (-1) * mcfcd.stations$lon # arizona is west of prime meridian so longitude should be negative

# in temp data, stations 1001 and 28301 are missing (both outside urbanized area, so not essential to replace)
# in temp data, station 1002 is extra (removed, station is humidity data w/ 0 < x > 100)
# in dewpt data, stations 30816 and 34916 are extra (removed, no stations w/ those IDs in index, data is consistent with dewpt data tho)

# bind station names to each data type, then full join all data together by station.name and date.time 
#(note: solar rad data is only every 30 min instead of other four at 15 min)
mcfcd.temp.data <- merge(mcfcd.temp.data, mcfcd.stations[,.(station.name,id)], by = "id")
mcfcd.dewpt.data <- merge(mcfcd.dewpt.data, mcfcd.stations[,.(station.name,id)], by = "id")
mcfcd.windir.data <- merge(mcfcd.windir.data, mcfcd.stations[,.(station.name,id)], by = "id")
mcfcd.winspd.data <-merge(mcfcd.winspd.data, mcfcd.stations[,.(station.name,id)], by = "id")
mcfcd.solar.data <- merge(mcfcd.solar.data, mcfcd.stations[,.(station.name,id)], by = "id")

mcfcd.data <- merge(mcfcd.temp.data[,.(date.time,station.name,temp.f)], mcfcd.dewpt.data[,.(date.time,station.name,dewpt.f)], by = c("date.time","station.name"), all = T)
mcfcd.data <- merge(mcfcd.data, mcfcd.windir.data[,.(date.time,station.name,windir)], by = c("date.time","station.name"), all = T)
mcfcd.data <- merge(mcfcd.data, mcfcd.winspd.data[,.(date.time,station.name,winspd)], by = c("date.time","station.name"), all = T)
mcfcd.data <- merge(mcfcd.data, mcfcd.solar.data[,.(date.time,station.name,solar)], by = c("date.time","station.name"), all = T)

# clean up space
rm(mcfcd.temp.data, mcfcd.dewpt.data, mcfcd.windir.data, mcfcd.winspd.data, mcfcd.solar.data, 
   temp.files, temp.names, dewpt.files, dewpt.names, windir.files, windir.names, winspd.files, winspd.names, solar.files, solar.names)
gc()

# create celcius temp/dew
mcfcd.data[, temp.c := ((temp.f - 32) / 1.8)]
mcfcd.data[, dewpt.c := ((dewpt.f - 32) / 1.8)]

# add data source column
mcfcd.data$source <- "MCFCD"
mcfcd.stations$source <- "MCFCD"

# filter out extraneous stations by sensor.type
mcfcd.stations <- mcfcd.stations[sensor.type %in% c("Temperature","Dewpoint","Wind Dir.","Peak Wind","Solar Rad.")]

# keep relevant columns only
mcfcd.stations <- mcfcd.stations[,c("source","station.name","lat","lon","elevation")]

# simplify station list
mcfcd.stations <- unique(mcfcd.stations)

# keep 2017 data only
mcfcd.data <- mcfcd.data[year(date.time) == 2017]


#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
# Import UWIN Phoenix iButton data  #
#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#

# import temp and rel humidity data
ibut.temp <- fread(here("data/weather data/iButton/phxbuttons.csv"))
ibut.rhum <- fread(here("data/weather data/iButton/phxbuttonsrh.csv"))

# import station info and data
ibut.stations <- fread(here("data/weather data/iButton/phxdatsite_all.csv"))
ibut.stations.col.info <- fread(here("data/weather data/iButton/phxdatsiteall_col_description.csv"))

# rename some cols
setnames(ibut.temp, "Date - Time", "date.time") 
setnames(ibut.rhum, "Date - Time", "date.time")
setnames(ibut.stations, "ibuttonID", "station.name")
setnames(ibut.stations, "Lat", "lat")
setnames(ibut.stations, "Lon", "lon")

# keep only relevant columns
ibut.stations <- ibut.stations[, .(station.name,lat,lon)]

# remove hour column
ibut.temp[, hour := NULL] 
ibut.rhum[, hour := NULL] 

# melt and recast temp & hum data b/c in wide format
ibut.temp <- melt(ibut.temp, id = "date.time", variable.name = "station.name", value.name = "temp.c")
ibut.rhum <- melt(ibut.rhum, id = "date.time", variable.name = "station.name", value.name = "rhum.c")

# format date.time as YYYY-MM-DD HH:MM:SS
ibut.temp[, date.time := mdy_hm(date.time, tz = "US/Arizona")]
ibut.rhum[, date.time := mdy_hm(date.time, tz = "US/Arizona")]

# round times of temp cause they are 1 min shifted off
ibut.temp[, date.time := as.POSIXct(round.POSIXt(date.time, "hours"))]

# bind temp and hum toegether by id & date.time
ibut.data <- merge(ibut.temp, ibut.rhum, by = c("date.time","station.name"), all = T)

# convert rhum to dewpt
ibut.data[, dewpt.c := humidity.to.dewpoint(rh = rhum.c, t = temp.c, temperature.metric = "celsius")]
ibut.data[, rhum.c := NULL] 

# create fahrenheit temp/dew
ibut.data[, temp.f := ((temp.c * 1.8) + 32)]
ibut.data[, dewpt.f := ((dewpt.c * 1.8) + 32)]

# add data source column
ibut.data$source <- "iButton"
ibut.stations$source <- "iButton"

# clean up space
rm(ibut.temp,ibut.rhum,ibut.stations.col.info)
gc()



## MESO WEST DATA RETREIVAL VIA API

# station metadata link w/o token
s.link <- "http://api.mesowest.net/v2/stations/metadata?state=AZ&county=Maricopa&status=ACTIVE&token="

# load personal api token (note you'll need your own)
token <- read_file(here("local-token.txt"))

# get station metadata (as JSON)
meso.metadata <- fromJSON(paste0(s.link,token))
meso.s.data <- as.data.table(meso.metadata$STATION)

# store partial weather data links (front half and variables list). time is local
w.link.f <- "http://api.mesowest.net/v2/stations/timeseries?&stid="
w.link.vars <- "&vars=air_temp,relative_humidity,wind_speed,wind_direction&obtimezone=local"

# [including in link] "timeformat=%b%20%d%20%Y%20-%20%H:%M" would yield "Jun 22 2017 - 17:06"

# define start and end times in correct format for api link retrieval
# AZ is -7 UTC, so leave a little space make sure and capture all records in calendar year
start <- "201701010600" # start time in YYYYMMDDhhmm (UTC)
end   <- "201801010800"   # end time in YYYYMMDDhhmm (UTC)

# loop through each station and retrieve sson data
meso.w.data <- list()
for(i in 1:nrow(meso.s.data)){ #
  
  # retieve json data for station 'i' based on start and end time, custom api token, and desired variables
  j <- fromJSON(paste0(w.link.f,meso.s.data$STID[i],"&start=",start,"&end=",end,"&token=",token,w.link.vars))
  
  # if there is data at the location, get it
  if(is_empty(j$STATION) == F){
    
    # coerce to data.table in list (need to unlist columns)
    meso.w.data[[i]] <- as.data.table(sapply(j$STATION$OBSERVATIONS, unlist))
    
    # if vars exists, rename it for consistency w/ other data
    if(is.null(meso.w.data[[i]]$date_time) == F){setnames(meso.w.data[[i]], "date_time", "date.time")}
    if(is.null(meso.w.data[[i]]$relative_humidity_set_1) == F){setnames(meso.w.data[[i]], "relative_humidity_set_1", "rh")}
    if(is.null(meso.w.data[[i]]$wind_speed_set_1) == F){setnames(meso.w.data[[i]], "wind_speed_set_1", "winspd")}
    if(is.null(meso.w.data[[i]]$wind_direction_set_1) == F){setnames(meso.w.data[[i]], "wind_direction_set_1", "windir")}
    if(is.null(meso.w.data[[i]]$air_temp_set_1) == F){setnames(meso.w.data[[i]], "air_temp_set_1", "temp.c")}
    
    # create station column name and list index name based on the station id (STID) for refrencing
    names(meso.w.data)[i] <- j$STATION$STID
    meso.w.data[[i]]$id <- j$STATION$STID
    meso.w.data[[i]]$station.name <- j$STATION$NAME
    meso.w.data[[i]]$qcflag <- j$STATION$QC_FLAGGED
  }
}

# create combined data option (all data in one data.table). this is more compact 
all.meso.w.data <- rbindlist(meso.w.data, use.names = T, fill = T)

# format date.time correctly (time is local so call AZ timezone). ignore "T" (for: time) in middle and -0700 at end (for: GMT/UTC +0700)
all.meso.w.data[, date.time := ymd_hms(paste(substr(date.time, 1, 10), substr(date.time, 12, 19)), tz = "US/Arizona")]

# force data columns to numeric
all.meso.w.data[, rh := as.numeric(rh)][, winspd := as.numeric(winspd)][, windir := as.numeric(windir)][, temp.c := as.numeric(temp.c)]

# trim to year 2017 weather obs only
all.meso.w.data <- all.meso.w.data[year(date.time) == 2017]

# create some vars
all.meso.w.data[, temp.f := signif((temp.c * 1.8) + 32, digits = 4)]
all.meso.w.data[, dewpt.c := humidity.to.dewpoint(rh = rh, t = temp.c, temperature.metric = "celsius")]
all.meso.w.data[, dewpt.f := humidity.to.dewpoint(rh = rh, t = temp.f, temperature.metric = "fahrenheit")]

# rename columns for consistency
setnames(meso.s.data, "NAME", "station.name")
setnames(meso.s.data, "STID", "id") # could use "ID" column here instead
setnames(meso.s.data, "ELEVATION", "elevation")
setnames(meso.s.data, "LONGITUDE", "lon")
setnames(meso.s.data, "LATITUDE", "lat")
  
# keep relevant columns only in station data
meso.s.data <- meso.s.data[, .(station.name,id,elevation,lat,lon)]

# add source column in station data
meso.s.data$source <- "MesoWest"


#^#^#^#^#^#^#^#^#^#^#^#^#^#
# Merge all data together #
#^#^#^#^#^#^#^#^#^#^#^#^#^#

# combine all houlry weather data into one object, and all stations into one object
w.data <- rbindlist(list(azmet.data,ncei.data,mcfcd.data,ibut.data,all.meso.w.data), use.names = T, fill = T)
w.stations <- rbindlist(list(azmet.stations,ncei.stations,mcfcd.stations,ibut.stations,meso.s.data), use.names = T, fill = T)

# coerce lat, lon, & elev to numeric
w.stations[, lat := as.numeric(lat)][, lon := as.numeric(lon)][, elevation := round(as.numeric(elevation), digits = 0)]

# calculate heat index, (National Weather Surface improved estimate of Steadman eqn. (heat index calculator eqns)
w.data[, heat.f := heat.index(t = temp.f, dp = dewpt.f, temperature.metric = "fahrenheit", output.metric = "fahrenheit", round = 0)]
w.data[, heat.c := heat.index(t = temp.c, dp = dewpt.c, temperature.metric = "celsius", output.metric = "celsius", round = 1)]

# add some other variables 
w.data[, month := as.factor(lubridate::month(date.time, label = T))]
w.data[, week := as.factor(lubridate::week(date.time))]
w.data[, day := as.factor(lubridate::day(date.time))]
w.data[, wday := as.factor(lubridate::wday(date.time, label = T))]
w.data[, hour := lubridate::hour(date.time)]

# create rounded data.time to more easily filter by observations on/near the hour
w.data[, date.time.round := as.POSIXct(round.POSIXt(date.time, "hours"))]

# calculate observations in 2017 for each station by each data type
for(i in 1:nrow(w.stations)){
  i.name <- w.stations$station.name[i]
  i.id <- w.stations$id[i]
  i.source <- w.stations$source[i]
  
  # NCEI
  if(i.source == "NCEI"){
    w.stations[station.name == i.name & source == i.source & id == i.id, n.temp := sum(!is.na(w.data$temp.f[i.name == w.data$station.name]))]}

  # MesoWest; use all.meso.w.data & temp.c
  if(i.source == "MesoWest"){
    w.stations[station.name == i.name & source == i.source & id == i.id, n.temp := sum(!is.na(w.data$temp.c[i.name == w.data$station.name & i.id == w.data$id]))]}
  
  # iButton; id is NA
  if(i.source == "iButton"){
    w.stations[station.name == i.name & source == i.source, n.temp := sum(!is.na(w.data$temp.f[i.name == w.data$station.name]))]}
  
  # AZMET; id is NA
  if(i.source == "AZMET"){
    w.stations[station.name == i.name & source == i.source, n.temp := sum(!is.na(w.data$temp.f[i.name == w.data$station.name]))]}
  
  # MCFCD; id is NA
  if(i.source == "MCFCD"){
    w.stations[station.name == i.name & source == i.source, n.temp := sum(!is.na(w.data$temp.f[i.name == w.data$station.name]))]}
}

# for id == NA, make them the station.name
w.stations[is.na(id), id := station.name]
w.data[is.na(id), id := station.name]

# save all final R objects
saveRDS(w.data, here("data/outputs/temp/2017-weather-data.rds")) # all houlry weather data
saveRDS(w.stations, here("data/outputs/temp/2017-station-data.rds")) # all station data

# save output in multiple files so it can sync to github
#saveRDS(w.data[1:floor(.N/3)], here("data/outputs/2017-weather-data-1.rds"))
#saveRDS(w.data[(floor(.N/3)+1):floor(.N*2/3)], here("data/outputs/2017-weather-data-2.rds"))
#saveRDS(w.data[(floor(.N*2/3)+1):(.N)], here("data/outputs/2017-weather-data-3.rds"))

# print script endtime
t.end <- Sys.time() 
paste0("Completed task at ", t.end, ". Task took ", round(difftime(t.end,t.start, units = "mins"),1)," minutes to complete.") # paste total script time
# end
