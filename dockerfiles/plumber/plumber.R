#* @get /mean
normalMean <- function(samples=10){
  data <- rnorm(samples)
  Sys.sleep(5)
  mean(data)
}

#* @post /sum
addTwo <- function(a, b){
  as.numeric(a) + as.numeric(b)
}

