# script name:
# Machine Learning API.R

#### Cara running API , copy command di bawah ini ke console :
# plumber::plumb(file='Machine Learning API.R')$run(port = 8000)

#* @apiTitle Machine Learning API
#* @apiDescription Simple API untuk demo

library(jsonlite)
library(dplyr)
library(rjson)

#* Log waktu , jenis request serta user agent untuk request yang dilakukan. Hanya sebagai info saja
#* @filter logger
function(req){
  cat("System time:", as.character(Sys.time()), "\n",
      "Request method:", req$REQUEST_METHOD, req$PATH_INFO, "\n",
      "HTTP user agent:", req$HTTP_USER_AGENT, "@", req$REMOTE_ADDR, "\n")
  plumber::forward()
}

#*@param pefindoID : ID pefindo dummy dari flask
#*@param nama : nama customer dummy dari flask
#* @post /pefindo
get_pefindo <- function(pefindoID,nama){
  id = pefindoID
  Nama = nama
  hasil <- floor(runif(1,min=210,max=300)) # random number generator untuk scoring
  return(list(score = unbox(hasil), ID = unbox(id)))
}

