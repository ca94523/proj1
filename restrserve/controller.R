library(RestRserve)
library(Rcpp)
library(plyr)
library(dplyr)
library(rpart)
library(zoo)
library(DBI)
library(RPostgreSQL)
library(psych)
library(stringr)
library(reshape)
library(lubridate)
library(timeDate)
library(data.table)
library(ROCR)
library("xgboost")
library(tidyr)
library(jsonlite)
library(tibble)

source("functions.R")

#### INSIALISASI APLIKASI ####
###
app = Application$new(content_type = "application/json")
app$logger$set_log_level("error")
filepath = getwd()

#### HANDLER UNTUK ENDPOINT /slik ####
###
slik_handler = function(.req, .res){
	Sys.sleep(10)
  #convert input ke dalam json
  input_to_json <- toJSON(.req$body,auto_unbox = TRUE)
  input_to_json <- prettify(input_to_json)
  
  #input di convert lagi ke json
  input_data <- fromJSON(input_to_json)
  app_data <- input_data[["DemographicData"]] # ambil data application dari json input
  
  #save json input ke local dir
  applicant_name <- toupper(app_data[["Name"]])
  file_date <- as.character(Sys.Date())
  file_time <- as.character(format(Sys.time(),"%H%M%S"))
  file_input <- as.character(paste(filepath,"/", applicant_name,"-",file_date,"-",file_time,"-INPUT-SLIK.json",sep = ""))
  write(input_to_json,file = file_input)

  # hitung PD score untuk data demografik
  pd_demog <- feature_engineering_demog(input_data)
  demog_data <- simple_rapply(app_data, function(x) if(is.null(x)) NA else x)
  demog_data <- as_tibble(demog_data)


  #---------- CEK APAKAH MEMILIKI DATA BIRO SLIK------------#
  slik_data <- input_data[['ResultIdeb']]

  # cek apakah slik data adalah list kosong atau NA

  if(length(slik_data) == 0 || is.na(slik_data)){

    #print("NO SLIK")
    hasil_slik <- data.frame("CRN" = demog_data$IDNumber, "xgb_bureau" = NA, "bureau" = "SLIK")

  } else {
    # hitung PD score untuk data SLIK

    #print("WITH SLIK")
    hasil_slik <- pdscore_bureau_slik(input_data)
    hasil_slik$CRN <- demog_data$IDNumber
    hasil_slik$bureau <- "SLIK"
  }

  #--------------------- CEK APAKAH NASABAH NTB/ETB  ------------------------ #
  if(demog_data$CustomerType == "NTB" | is.na(demog_data$CIF) | demog_data$CIF ==""){
    # nasabah NTB

    pd_final <- NTB_PDScore_final(hasil_slik,pd_demog)
    pd_all_module <- data.frame("xgb_bureau" = hasil_slik$xgb_bureau, "xgb_demog" = pd_demog$xgb_demog)
  }else if (demog_data$CustomerType == "ETB"){
    # nasabah ETB

    #### Ambil data dari database ####
    # connect to the database
    test_user <- Sys.getenv("USERNAME")
    test_pass <- Sys.getenv("PASSWORD")
    con <- dbConnect(PostgreSQL(), dbname= "spark_beyond", host = "10.255.4.8", port = "5432",
                     user = "postgres", password = "postgres")

    # close koneksi ke database setelah function bekerja
    on.exit(dbDisconnect(con))

    ### AMBIL DATA CIF UNTUK DARI JSON INPUT ###
    cif <- data.frame("cfcif_2" = demog_data[['CIF']])
    cif$cfcif_2 <- as.numeric(as.character(cif$cfcif_2)) # ubah data cif menjadi integer
    listcif = toString(sprintf("'%s'", unlist(cif$cfcif_2)))

    ### PENGECEKAN DI CFMAST ###
    sql_fmt =  " select cfcif_2, cforgd, scd_start from sb.cfmast where cfcif_2 in (%s) "
    sql_list = sprintf(sql_fmt, listcif)
    cfmast_data = dbGetQuery(con,sql_list)

    ### PENGECEKAN DI DDMAST ###
    sql_del_cif =  " select acctno,cifno, cbal, scd_start from sb.ddmast where cifno in (%s) "
    sql_del_ciflist = sprintf(sql_del_cif, listcif)
    ddmast_data = dbGetQuery(con,sql_del_ciflist)

    ### PENGECEKAN DI DDHIST ###
    if(length(ddmast_data) == 0){
      ddhist_data = data.frame()
    }else {
      ## Ambil data acctno yang distinct ##
      distinct_cif <- ddmast_data %>%
        distinct(acctno, cifno, .keep_all = TRUE)

      list_acct = toString(sprintf("'%s'", unlist(distinct_cif$acctno)))
      sql_ddhist =  " select tracct, trdorc, trloca, treffd,trbr from sb.ddhist where tracct in (%s) "
      sql_ddhist_acct = sprintf(sql_ddhist, list_acct)
      ddhist_data = dbGetQuery(con,sql_ddhist_acct)
    }

    pd_banking <- pdscore_banking(input_data,con,cfmast_data,ddmast_data,ddhist_data,listcif)
    pd_digital <- pdscore_digital(input_data,con,ddmast_data,ddhist_data,listcif)
    pd_final <- ETB_PDScore_final(hasil_slik,pd_demog,pd_banking,pd_digital)
    pd_all_module <- data.frame("pd_bureau" = hasil_slik$xgb_bureau, "pd_demog" = pd_demog$xgb_demog,
                                "pd_banking" = pd_banking$xgb_banking, "pd_digital" = pd_digital$xgb_digital)
  }
  
  # output untuk dikirim ke LOS
  json_output <- pd_final %>%
    mutate(KTP = IDNumber,
           PD_Score = pd)  %>%
    select(!c("IDNumber","pd"))
  #output untuk disimpan ke file JSON
  json_output_save <- cbind(pd_final,pd_all_module)
  json_output_return <- as.list(json_output)
  
  #simpan file output
  file_output <- as.character(paste(filepath,"/",applicant_name,"-",file_date,"-",file_time,"-OUTPUT-SLIK.json",sep = ""))
  write_json(json_output_save, file_output)

  .res$set_content_type("application/json")
  .res$set_body(json_output_return)
  
}


app$add_post(path = "/slik", FUN = slik_handler) ## ADD SLIK ENDPOINT

#### HANDLER UNTUK ENDPOINT /pefindo ####
###
pefindo_handler = function(.req, .res){
  
  # read request sebagai json
  requests <- .req$body
  request_to_json <- to_json(requests,unbox = T)
  
  # ubah request sebagai R object dari json
  input_data<- jsonlite::fromJSON(request_to_json)
  app_data <- input_data[["DemographicData"]] # ambil data application dari json input
  
  #save json input ke local dir
  applicant_name <- toupper(app_data[["Name"]])
  file_date <- as.character(Sys.Date())
  file_time <- as.character(format(Sys.time(),"%H%M%S"))
  file_input <- as.character(paste(filepath,"/",applicant_name,"-",file_date,"-",file_time,"-INPUT-PEFINDO.json",sep = ""))
  jsonlite::write_json(input_data, file_input)
  
  # hitung pd score untuk modul demografik
  pd_demog <- feature_engineering_demog(input_data)
  demog_data <- simple_rapply(app_data, function(x) if(is.null(x)) NA else x)
  demog_data <- as_tibble(demog_data)
  
  #---------- CEK APAKAH MEMILIKI DATA BIRO PEFINDO------------#
  pefindo_data<- input_data[['ReportInfo']]
  
  # cek apakah status report Report Generated atau tidak, atau jika data Contracts tersedia
  if(pefindo_data$ReportStatus != "ReportGenerated" || is.na(input_data[["Contracts"]])){
    #print("NO PEFINDO")
    pd_pef <- data.frame("CRN" = demog_data$IDNumber, "xgb_bureau" = NA, "bureau" = "pefindo")
  } else {
    
    # buat tabel pefindo untuk feature engineering
    #print("WITH PEFINDO")
    hasil <- pefindo_tables(input_data)
    CONTRACT_PAYMENT_CALENDAR_MASTER <- hasil[[1]]
    CONTRACT_SUMMARY_DEBTOR <- hasil[[2]]
    MASTER_DATA <- hasil[[3]]
    COLLA_MASTER <- hasil[[4]]
    
    # hitung PD score untuk data pefindo
    pd_pef <- pdscore_bureau_pefindo(CONTRACT_PAYMENT_CALENDAR_MASTER,CONTRACT_SUMMARY_DEBTOR,MASTER_DATA,COLLA_MASTER)
    pd_pef$CRN <- demog_data$IDNumber
    pd_pef$bureau <- "pefindo"
    #print(pd_pef)
  }
  
  #--------------------- CEK APAKAH NASABAH NTB/ETB  ------------------------ #
  if(demog_data$CustomerType == "NTB" | is.na(demog_data$CIF) | demog_data$CIF ==""){
    # nasabah NTB
    
    pd_final <- NTB_PDScore_final(pd_pef,pd_demog)
    pd_all_module <- data.frame("xgb_bureau" = pd_pef$xgb_bureau, "xgb_demog" = pd_demog$xgb_demog)
  }else if (demog_data$CustomerType == "ETB") {
    # nasabah ETB
    #### Ambil data dari database ####
    # connect to the database
    test_user <- Sys.getenv("USERNAME")
    test_pass <- Sys.getenv("PASSWORD")
    con <- dbConnect(PostgreSQL(), dbname= "spark_beyond", host = "10.255.4.8", port = "5432",
                     user = "postgres", password = "postgres")
    
    # close koneksi ke database setelah function bekerja
    on.exit(dbDisconnect(con))
    
    ### AMBIL DATA CIF UNTUK DARI JSON INPUT ###
    cif <- data.frame("cfcif_2" = demog_data[['CIF']])
    cif$cfcif_2 <- as.numeric(as.character(cif$cfcif_2)) # ubah data cif menjadi integer
    listcif = toString(sprintf("'%s'", unlist(cif$cfcif_2)))
    
    ### PENGECEKAN DI CFMAST ###
    sql_fmt =  " select cfcif_2, cforgd, scd_start from sb.cfmast where cfcif_2 in (%s) "
    sql_list = sprintf(sql_fmt, listcif)
    cfmast_data = dbGetQuery(con,sql_list)
    
    ### PENGECEKAN DI DDMAST ###
    sql_del_cif =  " select acctno,cifno, cbal, scd_start from sb.ddmast where cifno in (%s) "
    sql_del_ciflist = sprintf(sql_del_cif, listcif)
    ddmast_data = dbGetQuery(con,sql_del_ciflist)
    
    ### PENGECEKAN DI DDHIST ###
    if(length(ddmast_data) == 0){
      ddhist_data = data.frame()
    }else {
      ## Ambil data acctno yang distinct ##
      distinct_cif <- ddmast_data %>%
        distinct(acctno, cifno, .keep_all = TRUE)
      
      list_acct = toString(sprintf("'%s'", unlist(distinct_cif$acctno)))
      sql_ddhist =  " select tracct, trdorc, trloca, treffd,trbr from sb.ddhist where tracct in (%s) "
      sql_ddhist_acct = sprintf(sql_ddhist, list_acct)
      
      ddhist_data = dbGetQuery(con,sql_ddhist_acct) #mesti diedit datanya karena 0 data
    }
    
    pd_banking <- pdscore_banking(input_data,con,cfmast_data,ddmast_data,ddhist_data,listcif)
    pd_digital <- pdscore_digital(input_data,con,ddmast_data,ddhist_data,listcif)
    pd_final <- ETB_PDScore_final(pd_pef,pd_demog,pd_banking,pd_digital)
    pd_all_module <- data.frame("pd_bureau" = pd_pef$xgb_bureau, "pd_demog" = pd_demog$xgb_demog,
                                "pd_banking" = pd_banking$xgb_banking, "pd_digital" = pd_digital$xgb_digital)
  }
  
  # output untuk dikirim ke LOS
  json_output <- pd_final %>%
    mutate(KTP = IDNumber,
           PD_Score = pd)  %>%
    select(!c("IDNumber","pd"))
  
  
  #output untuk disimpan ke file JSON
  json_output_save <- cbind(pd_final,pd_all_module)
  json_output_return <- as.list(json_output)
  
  #simpan file output
  file_output <- as.character(paste(filepath,"/", applicant_name,"-",file_date,"-",file_time,"-OUTPUT-PEFINDO.json",sep = ""))
  jsonlite::write_json(json_output_save, file_output)

  .res$set_content_type("application/json")
  .res$set_body(json_output_return)
}
app$add_post(path = "/pefindo", FUN = pefindo_handler) ## ADD PEFINDO ENDOINT

backend = BackendRserve$new()
backend$start(app, http_port = 8080)