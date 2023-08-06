/*Kør ad-hoc*/
/*%include "G:\SASFolders\Planning\Utilities\SASProjectAutoexec.sas";*/

/*+
Program der danner rapport med DC ordreforslag.

/*- */
libname testd "G:\SMLK\Testdata\";
libname EU_DATA "\\sdksasprod\G$\SASFolders\Planning\Data";
libname EU_DIMP "\\sdksasprod\G$\SASFolders\Planning\;

/*Henter ordreforslaget*/
data dc_ordrer;
	set testd.dc_orders_total;
run;

/*Henter butikspræsentationslager*/
proc sql;
	create table presinv_stores as
		select distinct 
			sdknumber,
			sizeposition,
			sum(presentationinv) as presentationinv_store,
			count(distinct storeid) as noofstoreswithPI
		from pdetail.retailstorespace
			group by sdknumber, sizeposition;
quit;

/*Henter relevante felter i stamdata*/
proc sql;
	create table retailinv as
		select distinct 
			a.sdknumber,
			a.itemname,
			a.style,
			a.purchbatchsize,
			a.distributionbatchsize,
			a.presentationinvent as presentationinv_sdk,
			d.presentationinv_store,
			d.noofstoreswithPI,
			a.sizeposition,
			a.sizename,
			a.vendorid,
			a.leadtimevendor as leadtimevendor_sdk,
			a.colorid,
			a.colorname,
			a.costprice,
			a.purchaseprice,
			a.categoryno,
			a.catmgrexcelsheet,
			b.categoryname,
			b.categorymgr,
			a.itemgroupno,
			c.itemgroupname,
			a.purchcode,
			e.vendorleadtime as leadtimevendor_vend,
			e.minorderqty,
			f.vendorname
		from pdetail.retailinventtable a
			left join pdetail.categorynumberidtable b on a.categoryno = b.categoryno
			left join pdetail.itemgroupidtable c on a.itemgroupno = c.itemgroupno
			left join presinv_stores d on a.sdknumber = d.sdknumber and a.sizeposition = d.sizeposition
			left join pdetail.vendortable e on a.vendorid = e.vendorid
			left join eu_data.vendortable f on a.vendorid = f.vendorid;
quit;

/*Fjerner dubletter, da nogle vendornames er stavet forskelligt*/
proc sort data=retailinv nodupkey;
	by sdknumber sizeposition;
run;

/*Ordreforslag + stamdata*/
proc sql;
	create table dc_ordrer2 as
		select 
			a.*,
			b.*
		from dc_ordrer a
			left join retailinv b on a.sdknumber = b.sdknumber and a.sizeposition = b.sizeposition
				where a.period = 1;
quit;

/*Henter diverse salg og forecast til validering af output*/
proc sql;
	create table sales as
		select distinct
			sdknumber,
			sizeposition,
			datepart(transdate) as transdate format=date9.,
			sum(qty) as sales
		from pdetail.retailsales_actualsale
			group by sdknumber, sizeposition, (calculated transdate);
quit;

/*Salg seneste 30 dage*/
proc means data=sales noprint nway;
	where transdate >= today()-30;
	by sdknumber sizeposition;
	var sales;
	output out=sales_lm (drop=_FREQ_ _TYPE_) sum(sales) = sales_lm;
run;

/*Salg næste 30 dage sidste år*/
proc means data=sales noprint nway;
	where transdate <= today()-335 and transdate >= today()-365;
	by sdknumber sizeposition;
	var sales;
	output out=sales_nmly (drop=_FREQ_ _TYPE_) sum(sales) = sales_nmly;
run;

/*Forecast næste 30 dage*/
proc sql;
	create table predict_nm as 
		select distinct sdknumber, 
			sizeposition, 
			(sum(predict)) as predict_nm,
			(sum(budgetpredict)) as budgetpred_nm,
			use_standardprofile
		from pfore_o.finalsizestorepredict 
			where date between today() and today()+30 
				group by sdknumber, sizeposition;
quit;

/*Forecast næste 120 dage*/
proc sql;
	create table predict_n4m as 
		select distinct sdknumber, 
			sizeposition, 
			(sum(predict)) as predict_n4m,
			(sum(budgetpredict)) as budgetpred_n4m
		from pfore_o.finalsizestorepredict 
			where date between today() and today()+120 
				group by sdknumber, sizeposition;
quit;

/*Henter lagerbeholdninger dd.*/
proc sql;
	create table dctoday as
		select distinct
			sdknumber,
			sizeposition,
			sum(qty) as dc_qty
		from pdetail.todays_inventory_warehouse
			where Banner = 'SM'
				group by sdknumber, sizeposition;
quit;

proc sql;
	create table storetoday as
		select distinct
			sdknumber,
			sizeposition,
			sum(qty) as store_qty,
			count(distinct storeid) as noofstoreswithinv
		from pdetail.todays_inventory_stores
			where Banner = 'SM'
				group by sdknumber, sizeposition;
quit;

/*Antal butikker som har SKU i sortiment*/
proc sql;
	create table sortimentsku as 
		select distinct
			a.sdknumber,
			a.sizeposition,
			count(distinct b.storeid) as antalbutisort
		from pdetail.sas_assortmentgroupitem a
			left join pdetail.sas_assortmentgroupstore b on a.assortmentgroupid = b.assortmentgroupid
			left join pdetail.sas_assortmentgrouptable c on a.assortmentgroupid = c.assortmentgroupid
				where a.sdknumber ne 'Other' and datepart(c.startdate) <= today() <= datepart(c.enddate)
					group by a.sdknumber, a.sizeposition
						order by a.sdknumber, a.sizeposition;
quit;

/*Aktivt sortiment uden undtagelsesliste*/
proc sql;
	create table active_assortment as
		select distinct
			a.storeid,
			a.sdknumber,
			a.sizeposition
		from pdetail.sortiment a
			where exclude NE 1 and storeid NOT IN ('50001','50003','60000','63010','63020','63030','63040');
quit;

/*Butikslager dd.*/
proc sql;
	create table store_inventory as
		select distinct
			a.storeid,
			a.sdknumber,
			a.sizeposition,
			a.qty
		from pdetail.todays_inventory_stores a
			where storeid NOT IN ('50001','50003','60000','63010','63020','63030','63040');
quit;

/*Beregn gns. servicelevel dd.*/
proc sql;
	create table service_today as
		select distinct
			a.sdknumber,
			a.sizeposition,
			avg
		(case 
			when b.qty = 0 then 0 
			else 1 
		end)
	as service	
		from active_assortment a
			left join store_inventory b on a.storeid = b.storeid and a.sdknumber = b.sdknumber and a.sizeposition = b.sizeposition
				group by a.sdknumber, a.sizeposition;
quit;

/*Find næste levering til CL*/
proc sql;
	create table nextpurch as
		select distinct a.sdknumber,
			a.sizeposition,
			min(datepart(a.deliverydate)) as nextdeldate format=date9.,
			sum(a.qty) as nextpurch
		from pdetail.purchaseorders a
			left join dc_ordrer2 b on a.sdknumber = b.sdknumber and a.sizeposition = b.sizeposition
				where b.period = 1 and a.ordertype in ('Lager','CL')
					group by a.sdknumber, a.sizeposition
						having datepart(a.deliverydate) = min(datepart(a.deliverydate));
quit;

/*Samler alt*/
data dc_ordrer_final;
	merge dc_ordrer2(in=dc) sales_lm sales_nmly predict_nm predict_n4m dctoday storetoday sortimentsku service_today nextpurch;
	by sdknumber sizeposition;

	if dc;
	orderupminusbacklog = orderuptolevel - backlog;
	moh_lm = forslag/sales_lm;
	moh_nmly = forslag/sales_nmly;
	moh_predict = forslag/predict_nm;
	moh_predictn4m = forslag/(predict_n4m/4);
	moh_predn4m_orderup = orderupminusbacklog/(predict_n4m/4);
	purchvalue = purchaseprice*forslag;
	openpurchvalue = purchaseprice*restordre_tot;
	presinvtot = sum(presentationinv_store,(antalbutisort-noofstoreswithPI)*presentationinv_sdk);
	presinvtotvalue = presinvtot*purchaseprice;
	itemdesc = strip(sdknumber)||' : '||strip(itemname)||' : '||strip(put(sizeposition,2.))||'-'||strip(sizename);
	leadtime = coalesce(leadtimevendor_sdk,leadtimevendor_vend,30);
	dc_qty = coalesce(dc_qty,0);
	store_qty = coalesce(store_qty,0);
	vendor = vendorid||':'||vendorname;
	dessinnr = strip(style)||' - '||strip(colorid);

	if presentationinv_sdk in (.,0) then
		noofstoreswithPI2 = noofstoreswithPI;
	else noofstoreswithpi2 = antalbutisort;
	drop noofstoreswithPI;
	rename noofstoreswithPI2 = noofstoreswithPI;

	if vendorid ne '123';
run;
%_load_data_to_VA(dc_ordrer_final, work, valibla);


/*Lav SKU forecast 12 mdr. ud i fremtiden*/

/*Størrelsesprofiler*/
proc means data = pdetail.abt1 noprint nway;
	class sdkNumber sizePosition;
	var qty;
	output out = sizePosSale (DROP=_TYPE_ _FREQ_)
		sum(qty) = 
	;
run;

proc means data = pdetail.abt1 noprint nway;
	class sdkNumber;
	var transdate;
	output out = sdkDates (DROP=_TYPE_ _FREQ_)
		min(transdate) = min_date
		max(transdate) = max_date
	;
run;

proc means data = pdetail.abt1 noprint nway;
	class sdkNumber;
	var qty;
	output out = sdkTotal (DROP=_TYPE_ _FREQ_)
		sum(qty) = totqty
	;
run;

data sizeprof;
	merge sizePosSale 
		sdkDates
		sdkTotal;
	by sdknumber;
	sizeweight = qty/totqty;
run;

proc sort data=sizeprof;
	by sdknumber sizeposition;
run;

proc sort data=pamart.retailinventtable(drop=sizeposition sizename counter) out=retailinv nodupkey;
	by sdknumber;
run;

proc sql;
	create table skuforecastpre as
		select distinct
			a.sdknumber,
			a.date,
			sum(a.predict) as predict
		from pfore_o.sdknumber_forecast a
			left join retailinv b on a.sdknumber = b.sdknumber
				where a.date between today() and today()+365
					group by a.sdknumber, a.date;
quit;

proc sql;
	create table skuforecast as
		select distinct
			a.*,
			d.sizeposition,
			a.date-c.leadtime as purchdate format=date9.,
			c.vendorid,
			d.sizeweight,
			c.leadtime,
			b.sizename,
			year(calculated purchdate) as year,
			month(calculated purchdate) as month,
			intnx('month',(calculated purchdate),0,'b') as primo_month format=date9.,
			strip(a.sdknumber)||' : '||strip(b.itemname)||' : '||strip(put(d.sizeposition,2.))||'-'||strip(b.sizename) as itemdesc,
			round((predict*d.sizeweight),1) as skupredict
		from skuforecastpre a
			left join sizeprof d on a.sdknumber = d.sdknumber
				inner join dc_ordrer_final c on a.sdknumber = c.sdknumber and d.sizeposition = c.sizeposition
					left join pamart.retailinventtable b on a.sdknumber = b.sdknumber and b.sizeposition = c.sizeposition
						group by a.sdknumber, a.date;
quit;
%_load_data_to_VA(skuforecast, work, valibla);

/*Forsøgsbasis - lav forslag til historisk SDK*/
/*Udvælg kun NOOS-varer (SASPurchase = J) og frasorter Vendor 123*/
proc sql;
	create table noos_sdk as
		select distinct sdknumber,
			historicsdknumber,
			itemgroupno,
			itemgroupname
		from pamart.retailinventtable
			where saspurchase in ('J','j','Y','y') and VendorId NE '123';
quit;

/*Find nye NOOS-varer som enten har under 10 stk. solgt eller første salgsdato indenfor seneste måned*/
proc sql;
	create table saleprsdk as
		select distinct 
			a.sdknumber,
			b.historicsdknumber,
			b.itemgroupno,
			b.itemgroupname,
			min(datepart(a.transdate)) as firstsale format=date9.,
			coalesce(sum(a.qty),0) as totsales
		from pdetail.retailsales_actualsale a
			inner join noos_sdk b on a.sdknumber = b.sdknumber
				group by a.sdknumber
					having (calculated totsales) < 10 or (calculated firstsale) >= today()-30
	;
quit;

proc sql;
	create table saleprsdkref as
		select distinct 
			a.sdknumber,
			b.itemgroupno,
			b.itemgroupname,
			min(datepart(a.transdate)) as firstsale format=date9.,
			max(datepart(a.transdate)) as lastsale format=date9.,
			(calculated lastsale)-(calculated firstsale) as daysofsale,
			coalesce(sum(a.qty),0) as totsales
		from pdetail.retailsales_actualsale a
			left join pamart.retailinventtable b on a.sdknumber = b.sdknumber
				where datepart(a.transdate) >= '1jan2017'd
					group by a.sdknumber
						having (calculated totsales) > 75 or (calculated daysofsale) >= 150
	;
quit;

proc sql;
	create table saleprsdkquarter as
		select distinct 
			a.sdknumber,
			count(distinct year(datepart(transdate))) as noofyears,
		(case 
			when month(datepart(transdate)) in (1,2,3) then coalesce(a.qty,0)/(calculated noofyears) 
			else 0 
		end)
	as q1sales,
		(case 
			when month(datepart(transdate)) in (4,5,6) then coalesce(a.qty,0)/(calculated noofyears) 
			else 0 
		end)
	as q2sales,
		(case 
			when month(datepart(transdate)) in (7,8,9) then coalesce(a.qty,0)/(calculated noofyears) 
			else 0 
		end)
	as q3sales,
		(case 
			when month(datepart(transdate)) in (10,11,12) then coalesce(a.qty,0)/(calculated noofyears) 
			else 0 
		end)
	as q4sales,
		coalesce(sum(a.qty),0) as totsales
	from pdetail.retailsales_actualsale a
		where datepart(a.transdate) >= '1jan2017'd
			group by a.sdknumber
	;
quit;

proc sql;
	create table sdkwithprices as
		select distinct a.sdknumber,
			a.itemgroupno,
			a.itemgroupname,
			a.itemname,
			a.vendorname,
			coalesce(a.smrecommendedrp,a.recommendedrp) as recommrp
		from pamart.retailinventtable a
			inner join saleprsdkref b on a.sdknumber = b.sdknumber
				order by itemgroupno, sdknumber;
quit;

proc fastclus data=sdkwithprices maxclusters=10 noprint out=test;
	var recommrp;
	by itemgroupno;
run;