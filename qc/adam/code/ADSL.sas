/*****************************************************************************\
*        O                                                                      
*       /                                                                       
*  O---O     _  _ _  _ _  _  _|                                                 
*       \ \/(/_| (_|| | |(/_(_|                                                 
*        O                                                                      
* ____________________________________________________________________________
* Sponsor              : Domino
* Study                : H2QMCLZZT
* Program              : ADSL.SAS
* Purpose              : To create the qc ADaM ADSL dataset
* ____________________________________________________________________________
* DESCRIPTION                                                    
*                                                                   
* Input files:  SDTM: DM, EX, DS, SV, MH, QS, VS, SC
*              
* Output files: adamqc.ADSL
*               
* Macros:       None
*         
* Assumptions: 
*
* ____________________________________________________________________________
* PROGRAM HISTORY                                                         
*  9JUN2022  | Jake Tombeur  | Original version
\*****************************************************************************/

*********;
** Setup environment including libraries for this reporting effort;
%include "!DOMINO_WORKING_DIR/config/domino.sas";
*********;

**** USER CODE FOR ALL DATA PROCESSING **;

%let keepvars = STUDYID USUBJID SUBJID SITEID SITEGR1 ARM TRT01P TRT01PN TRT01A TRT01AN RFSTDTC RFENDTC RFXSTDTC RFXENDTC 
                LSTEXDTC EOSSTT EOSDT EOSDY DCSREAS DCSREAPL RANDDT TRTSDT TRTEDT TRTDURD CUMDOSE AVGDD AGE AGEGR1 AGEGR1N AGEU
                RACE RACEN SEX ETHNIC RANDFL ITTFL SAFFL EFFFL COMPLFL COMP8FL COMP16FL COMP26FL DTHFL DTHDTC DTHDT BMIBL BMIGR1 HEIGHTBL WEIGHTBL
                EDLEVEL DISONDT VIS1DT DURDISM DURDSGR1 VISNUMEN BLDSEV;

* -----------------------------------------------------------------------------------------------------------------;
* Read in data from DM and exclude screen failures;
data dm (keep = studyid usubjid subjid siteid arm rfstdtc rfendtc rfxstdtc rfxendtc age ageu race sex ethnic dthfl dthdtc dthdt);
	set sdtm.dm (where = (upcase(arm) ne "SCREEN FAILURE"));

  if (length(dthdtc) ge 10) then dthdt = input(substr(dthdtc,1,10), e8601da.);
run;


* -----------------------------------------------------------------------------------------------------------------;
* Read in data from EX to derive last exposure date;
data ex1;
  set sdtm.ex;
run;

proc sort data = ex1;
  by usubjid visitnum;
run;

data ex (keep = usubjid exendtc rename = (exendtc = lstexdtc));
  set ex1;
    by usubjid;
  if last.usubjid;
run;

* -----------------------------------------------------------------------------------------------------------------;
* Read in data from DS to get end of study information;
data ds (keep = usubjid visitnum dsdecod dscat);
  set sdtm.ds (where = (upcase(dscat) eq "DISPOSITION EVENT" and upcase(dsdecod) ne "SCREEN FAILURE"));
run;

* -----------------------------------------------------------------------------------------------------------------;
* Read in data from QS to check if subject has data for EFFFL;
data qs1 (keep = usubjid qstestcd hasdata);
  set sdtm.qs (where = (qstestcd in ("ACTOT","CIBIC") and visitnum gt 3 and qsstresn ne .));
  hasdata = 1;
run;

proc sort data = qs1;
  by usubjid qstestcd hasdata;
run;

data qs2;
  set qs1;
    by usubjid qstestcd hasdata;
  if last.hasdata;
run;

proc transpose data = qs2 out = qs (keep = usubjid actot cibic);
  var hasdata;
  id  qstestcd;
  by  usubjid;
run;

* -----------------------------------------------------------------------------------------------------------------;
* Read in data from SV for completion flags;
data sv1 (keep = usubjid visitnum svstdt);
  set sdtm.sv (where = (visitnum in (1,8,10,12)));

  if (length(svstdtc) ge 10) then svstdt = input(substr(svstdtc,1,10), e8601da.);
  format svstdt date9.;
run;

* Get numeric visit dates across;
proc transpose data = sv1 out = sv (drop = _name_) prefix = svst_;
  var svstdt;
  id  visitnum;
  by  usubjid;
run;

* -----------------------------------------------------------------------------------------------------------------;
* Read in data from SV for randomization date;
data rn (keep = usubjid randdt);
  set sdtm.sv (where = (visitnum eq 3));

  if (length(svstdtc) ge 10) then randdt = input(substr(svstdtc,1,10), e8601da.);
  format randdt date9.;
run;

* -----------------------------------------------------------------------------------------------------------------;
* Read in data from VS for baseline height and weight;
data ht (keep = usubjid vsstresn rename = (vsstresn = heightbl));
  set sdtm.vs (where = (vstestcd eq "HEIGHT" and visitnum eq 1 and vsstresn ne .));
run;

data wt (keep = usubjid vsstresn rename = (vsstresn = weightbl));
  set sdtm.vs (where = (vstestcd eq "WEIGHT" and visitnum eq 3 and vsstresn ne .));
run;

* -----------------------------------------------------------------------------------------------------------------;
* Read in data from SC for education level;
data sc (keep = usubjid scstresn rename = (scstresn = edlevel));
  set sdtm.sc (where = (sctestcd eq "EDLEVEL" and scstresn ne .));
run;

* -----------------------------------------------------------------------------------------------------------------;
* Read in data from MH for disease onset;
data mh (keep = usubjid disondt);
  set sdtm.mh (where = (mhcat eq "PRIMARY DIAGNOSIS" and mhstdtc ne ""));

  if (length(mhstdtc) ge 10) then disondt = input(substr(mhstdtc,1,10), e8601da.);
run;

* -----------------------------------------------------------------------------------------------------------------;
* Read in data from QS for baseline MMSE;
data mmse1 (keep = usubjid qsstresn);
  set sdtm.qs (where = (qscat eq "MINI-MENTAL STATE" and qsstresn ne .));
run;

proc univariate data = mmse1 noprint;
  var qsstresn;
  by  usubjid;
  output out = mmse (keep = usubjid bldsev)
    n = n
	sum = bldsev
  ;
run;

* -----------------------------------------------------------------------------------------------------------------;
* Merge datasets together;
data adsl1;
  merge dm (in = d) ex ds qs sv rn ht wt sc mh mmse;
    by usubjid;
  if d;
run;

* -----------------------------------------------------------------------------------------------------------------;
* Derive variables from merged data;
data adsl2;
	length dcsreapl $27 dcsreas $18 eosstt $12 sitegr1 $3 trt01p trt01a $20 randfl ittfl saffl efffl complfl comp8fl comp16fl comp26fl $1 agegr1 $5 bmigr1 $6 durdsgr1 $4;
  set adsl1;

  * Pool sites into SITEGR1;
  if (siteid not in ("702","706","707","711","714","715","717")) then sitegr1 = trim(left(siteid));
  else if (siteid in ("702","706","707","711","714","715","717")) then sitegr1 = "900";

  * Treatment variables;
  trt01p = trim(left(arm));
  trt01a = trim(left(trt01p));
  select (upcase(trt01p));
    when ("PLACEBO")                trt01pn = 0;
	when ("XANOMELINE LOW DOSE")    trt01pn = 54;
	when ("XANOMELINE HIGH DOSE")   trt01pn = 81;
	otherwise put "NO" "TE: check values " usubjid= trt01p=;
  end;
  select (upcase(trt01a));
    when ("PLACEBO")                trt01an = 0;
	when ("XANOMELINE LOW DOSE")    trt01an = 54;
	when ("XANOMELINE HIGH DOSE")   trt01an = 81;
	otherwise put "NO" "TE: check values " usubjid= trt01a=;
  end;

  * End of study status;
  if       (upcase(dsdecod) eq "COMPLETED" & upcase(dscat) = 'DISPOSITION EVENT') then eosstt = "COMPLETED";
  else if  (upcase(dsdecod) ^= "COMPLETED" & upcase(dscat) = 'DISPOSITION EVENT') then eosstt = "DISCONTINUED";

  * Reason for discontinuation;
  if (upcase(dsdecod) ne "COMPLETED") then do;
    dcsreas = trim(left(dsdecod));

    select (upcase(dcsreas));
      when ("ADVERSE EVENT")                 dcsreapl = "Adverse Event";
	  when ("DEATH")                         dcsreapl = "Death";
	  when ("LACK OF EFFICACY")              dcsreapl = "Lack of Efficacy";
	  when ("LOST TO FOLLOW-UP")             dcsreapl = "Lost to Follow-up";
	  when ("PHYSICIAN DECISION")            dcsreapl = "Physician Decision";
	  when ("PROTOCOL VIOLATION")            dcsreapl = "Protocol Violation";
	  when ("STUDY TERMINATED BY SPONSOR")   dcsreapl = "Sponsor Decision";
	  when ("WITHDRAWAL BY SUBJECT")         dcsreapl = "Withdrew Consent";
	  otherwise put "NO" "TE: check values " usubjid= dcsreas=;
    end;
  end;

  * End of study date and day;
  if (length(rfendtc) ge 10) then eosdt = input(substr(rfendtc,1,10),e8601da.);

  if (length(rfstdtc) ge 10) and (length(rfendtc) ge 10) then eosdy = input(substr(rfendtc,1,10),e8601da.) - input(substr(rfstdtc,1,10),e8601da.) + 1;

  * Treatment dates and duration;
  if (length(rfxstdtc) ge 10) then trtsdt = input(substr(rfxstdtc,1,10),e8601da.);

  if (length(lstexdtc) ge 10)                  then trtedt = input(substr(lstexdtc,1,10),e8601da.);
  else if (lstexdtc eq "") and (visitnum gt 3) then trtedt = eosdt;

  if (trtsdt ne .) and (trtedt ne .) then trtdurd = trtedt - trtsdt + 1;

  * Age groups;
  if (age ne .) then do;
    if (age lt 65) then do;
      agegr1  = "<65";
	  agegr1n = 1;
	end;
	else if (age ge 65) and (age le 80) then do;
      agegr1  = "65-80";
	  agegr1n = 2;
	end;
	else if (age gt 80) then do;
      agegr1  = ">80";
	  agegr1n = 3;
	end;
  end;

  * Race code;
  select (upcase(race));
    when ("WHITE")                             racen = 1;
	when ("BLACK OR AFRICAN AMERICAN")         racen = 2;
	when ("ASIAN")                             racen = 3;
	when ("AMERICAN INDIAN OR ALASKA NATIVE")  racen = 6;
	otherwise put "NO" "TE: check values " usubjid= race=;
  end;

  * Population flags;
  if (arm ne "") then randfl = "Y";
  else randfl = "N";

  ittfl = trim(left(randfl));

  if (ittfl eq "Y") and (trtsdt ne .) then saffl = "Y";
  else saffl = "N";

  if (saffl eq "Y") and (actot eq 1) and (cibic eq 1) then efffl = "Y";
  else efffl = "N";

  * Completers flags;
  if (svst_12 ne .) and (eosdt ne .) and (eosdt ge svst_12) then complfl = "Y";
  else complfl = "N";

  if (svst_8 ne .) and (eosdt ne .) and (eosdt ge svst_8) then comp8fl = "Y";
  else comp8fl = "N";

  if (svst_10 ne .) and (eosdt ne .) and (eosdt ge svst_10) then comp16fl = "Y";
  else comp16fl = "N";

  if (upcase(eosstt) eq "COMPLETED") then comp26fl = "Y";
  else comp26fl = "N";

  * BMI and group;
  if (heightbl ne .) then heightbl = round(heightbl,0.1);
  if (weightbl ne .) then weightbl = round(weightbl,0.1);
  if (weightbl ne .) and (heightbl ne .) then bmibl = round(weightbl / ((heightbl/100)*(heightbl/100)),0.1);

  if (bmibl ne .) then do;
    if (bmibl lt 25)                        then bmigr1  = "<25";
	else if (bmibl ge 25) and (bmibl lt 30) then bmigr1  = "25-<30";
	else if (bmibl ge 30)                   then bmigr1  = ">=30";
  end;

  * Visit 1 date;
  if (svst_1 ne .) then vis1dt = svst_1;

  * Duration of disease and group;
  if (vis1dt ne .) and (disondt ne .) then durdism = intck("month", disondt, vis1dt, "C");

  if (durdism ne .) then do;
    if (durdism lt 12)      then durdsgr1  = "<12";
	else if (durdism ge 12) then durdsgr1  = ">=12";
  end;

  * End of treatment visit;
  if (visitnum eq 13) and (eosstt eq "COMPLETED") then visnumen = 12;
  else if (eosstt eq "DISCONTINUED")              then visnumen = min(visitnum,12);
run;

* -----------------------------------------------------------------------------------------------------------------;
* Derive cumulative dose and average daily dose;
data dose1 (keep = usubjid exdose exendy exstdy);
  set sdtm.ex;
run;

proc sort data = dose1;
  by usubjid;
run;

proc sort data = adsl2;
  by usubjid;
run;

data dose2;
  merge adsl2 (keep = usubjid trtsdt trtedt) dose1;
    by usubjid;
run;

data dose3;
  set dose2;
  if (exstdy ne .) and (exendy ne .) and (exdose ne .)      then dose = exdose * (exendy - exstdy + 1);
  else if (exstdy ne .) and (exendy eq .) and (exdose ne .) then dose = exdose * ((trtedt-trtsdt+1) - exstdy + 1);
run;

data cumdose;
  set dose3;
    by usubjid;
  if first.usubjid then cumdose = 0;
  cumdose + dose;
  if last.usubjid;
run;

data adsl;
  merge adsl2 cumdose;
    by usubjid;

  avgdd = round(cumdose / trtdurd,0.1);
run;

data adamqc.adsl (label = "Subject-Level Analysis Dataset");
  retain &keepvars.;
  

  attrib
    STUDYID  length = $12 label = "Study Identifier"
    USUBJID  length = $11 label = "Unique Subject Identifier"
    SUBJID   length = $4  label = "Subject Identifier for the Study"
    SITEID   length = $3  label = "Study Site Identifier"
    SITEGR1  length = $3  label = "Pooled Site Group 1"
    ARM      length = $20 label = "Description of Planned Arm"
    TRT01P   length = $20 label = "Planned Treatment for Period 01"
    TRT01PN               label = "Planned Treatment for Period 01 (N)"
    TRT01A   length = $20 label = "Actual Treatment for Period 01"
    TRT01AN               label = "Actual Treatment for Period 01 (N)"
    RFSTDTC  length = $10 label = "Subject Reference Start Date/Time"
    RFENDTC  length = $10 label = "Subject Reference End Date/Time"
    RFXSTDTC length = $20 label = "Date/Time of First Study Treatment"
    RFXENDTC length = $20 label = "Date/Time of Last Study Treatment"
    LSTEXDTC length = $10 label = "Date/Time of Last End of Exposure"
    EOSSTT   length = $12 label = "End of Study Status"
    EOSDT                 label = "End of Study Date"
    EOSDY                 label = "End of Study Day"
    DCSREAS  length = $18 label = "Reason for Discontinuation from Study"
    DCSREAPL length = $27 label = "Reason for Disc from Study (Pooled)"
	RANDDT                label = "Date of Randomization"
    TRTSDT                label = "Date of First Exposure to Treatment"
    TRTEDT                label = "Date of Last Exposure to Treatment"
    TRTDURD               label = "Total Treatment Duration (Days)"
    CUMDOSE               label = "Cumulative Dose (as planned)"
    AVGDD                 label = "Avg Daily Dose (as planned)"
    AGE                   label = "Age"
    AGEGR1   length = $5  label = "Pooled Age Group 1"
    AGEGR1N               label = "Pooled Age Group 1 (N)"
    AGEU     length = $6  label = "Age Units"
    RACE     length = $78 label = "Race"
    RACEN                 label = "Race (N)"
    SEX      length = $1  label = "Sex"
    ETHNIC   length = $25 label = "Ethnicity"
    RANDFL   length = $1  label = "Randomized Population Flag"
    ITTFL    length = $1  label = "Intent-To-Treat Population Flag"
    SAFFL    length = $1  label = "Safety Population Flag"
    EFFFL    length = $1  label = "Efficacy Population Flag"
    COMPLFL  length = $1  label = "Completers Population Flag"
    COMP8FL  length = $1  label = "Completers of Week 8 Population Flag"
    COMP16FL length = $1  label = "Completers of Week 16 Population Flag"
    COMP26FL length = $1  label = "Completers of Week 26 Population Flag"
    DTHFL    length = $1  label = "Subject Death Flag"
	DTHDTC   length = $20 label = "Date/Time of Death"
    DTHDT                 label = "Date of Death"
    BMIBL                 label = "Baseline BMI (kg/m2)"
    BMIGR1   length = $6  label = "Pooled Baseline BMI Group 1"
    HEIGHTBL              label = "Baseline Height (cm)"
    WEIGHTBL              label = "Baseline Weight (kg)"
    EDLEVEL               label = "Years of Education Completed"
    DISONDT               label = "Date of Disease Onset"
    VIS1DT                label = "Date of Visit 1"
    DURDISM               label = "Duration of Disease (Months)"
    DURDSGR1 length = $4  label = "Pooled Disease Duration Group 1"
    VISNUMEN              label = "End of Trt Visit (Vis 12 or Early Term.)"
    BLDSEV                label = "Baseline Disease Severity (MMSE)"
  ;

	set adsl (keep = &keepvars.);
  format 
    trtsdt trtedt disondt vis1dt dthdt date9.
  ;
run;


**** END OF USER DEFINED CODE **;

/* ********; */
/* %s_scanlog; */
/* ********; */