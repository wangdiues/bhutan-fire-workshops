# Review audit using packaged data only. No folders created and no legacy GIS layers overwritten.
source(if (file.exists("thimphu_WUI/R/tw_common.R")) "thimphu_WUI/R/tw_common.R" else "R/tw_common.R")
Sys.setenv(TZ = "Asia/Thimphu")
set.seed(20261123)
terraOptions(progress = 0, memfrac = .5)
out <- function(x, name) write.csv(x, tw("data/derived", name), row.names = FALSE)
g <- grid50(); inside <- which(values(g, mat = FALSE) %in% 2); km2 <- (RES / 1000)^2
ob <- st_read(tw("data/derived/wui_thimphu.gpkg"), "buildings", quiet = TRUE)
fe <- tw("data/inputs/fire_evidence.gpkg")
dp <- st_read(fe, "dofps_points", quiet = TRUE)
fp <- st_read(fe, "firms_points", quiet = TRUE)
bp <- st_read(fe, "burned_patches", quiet = TRUE)

# Source record inventory. Shared DoFPS IDs are retained as direct linkage evidence.
ev <- rbind(
  data.frame(source="DoFPS", record_id=dp$event_id, reported_event_id=dp$event_id, date=as.character(dp$start_date_local)),
  data.frame(source="FIRMS", record_id=fp$detection_id, reported_event_id=NA_character_, date=substr(fp$acquired_datetime_utc,1,10)),
  data.frame(source="burned_patch", record_id=bp$patch_id, reported_event_id=bp$event_id, date=as.character(bp$fire_date)))
# Convert FIRMS UTC timestamps to local dates before event linkage.
ev$date[ev$source == "FIRMS"] <- format(as.POSIXct(fp$acquired_datetime_utc, format="%Y-%m-%dT%H:%M:%SZ", tz="UTC"), tz="Asia/Thimphu", format="%Y-%m-%d")
geom <- c(st_geometry(dp), st_geometry(fp), st_geometry(bp))
near <- st_is_within_distance(geom, dist = 1000)
days <- as.numeric(as.Date(ev$date)); parent <- seq_len(nrow(ev))
root <- function(i) { while (parent[i] != i) i <- parent[i]; i }
join <- function(i,j) { a <- root(i); b <- root(j); if (a != b) parent[b] <<- a }
for (i in seq_len(nrow(ev))) {
  for (j in near[[i]][near[[i]] > i]) if (!is.na(days[i]) && !is.na(days[j]) && abs(days[i]-days[j]) <= 3) join(i,j)
}
for (id in unique(na.omit(ev$reported_event_id))) {
  ix <- which(ev$reported_event_id == id); for (j in ix) join(ix[1],j)
}
ev$provisional_event_id <- sprintf("PE%04d", match(vapply(seq_len(nrow(ev)), root, 1L), unique(vapply(seq_len(nrow(ev)), root, 1L))))
ev$linkage_status <- "provisional: shared reported ID or connected within 1 km and 3 local days; manual adjudication required"
out(ev, "fire_event_record_inventory.csv")
events <- do.call(rbind, lapply(split(ev, ev$provisional_event_id), function(x) data.frame(
  provisional_event_id=x$provisional_event_id[1], first_date=min(x$date,na.rm=TRUE), last_date=max(x$date,na.rm=TRUE),
  n_records=nrow(x), n_dofps=sum(x$source=="DoFPS"), n_firms=sum(x$source=="FIRMS"), n_patches=sum(x$source=="burned_patch"),
  n_sources=length(unique(x$source)), reported_ids=paste(unique(na.omit(x$reported_event_id)),collapse=";"))))
out(events, "fire_event_summary.csv")

# Source-specific evaluations use the same 50 m raster distance construction as script 03.
dist_buildings <- function(x, polygon=FALSE) {
  r <- rasterize(vect(x), g, field=1, touches=polygon)
  values(distance(r), mat=FALSE)[cellFromXY(g, st_coordinates(ob))]
}
dd <- cbind(DoFPS=dist_buildings(dp), FIRMS=dist_buildings(fp), burned_patch=dist_buildings(bp,TRUE), combined=ob$dist_fire_all_m)
metrics <- function(w,e) {
  tp<-sum(w&e); fn<-sum(!w&e); fp<-sum(w&!e); tn<-sum(!w&!e)
  ratio <- function(a,b) if (b>0) a/b else NA_real_
  se<-ratio(tp,tp+fn); sp<-ratio(tn,tn+fp)
  c(tp=tp,fn=fn,fp=fp,tn=tn,prevalence=mean(e),sensitivity=se,specificity=sp,
    balanced_accuracy=(se+sp)/2,PPV=ratio(tp,tp+fp),NPV=ratio(tn,tn+fn),J=se+sp-1)
}
units<-sort(unique(ob$unit)); rows<-list(); ci<-list()
for (s in colnames(dd)) for (rule in c("legacy_fire_selected","structural_baseline")) {
  w<-ob[[if(rule=="legacy_fire_selected") "class_calibrated" else "class_baseline"]] %in% CLASSES[1:2]
  e<-dd[,s]<=1000; m<-metrics(w,e)
  rows[[length(rows)+1]]<-data.frame(source=s,rule=rule,as.list(m),check.names=FALSE)
  bt<-replicate(1000,{ us<-sample(units,length(units),replace=TRUE); ix<-unlist(lapply(us,function(u) which(ob$unit==u))); metrics(w[ix],e[ix]) })
  for (k in c("sensitivity","specificity","balanced_accuracy","PPV","NPV","J")) {
    z<-bt[k,]; q<-quantile(z,c(.025,.975),na.rm=TRUE)
    ci[[length(ci)+1]]<-data.frame(source=s,rule=rule,metric=k,estimate=m[k],low=q[1],high=q[2],finite_replicates=sum(is.finite(z)),clusters=length(units),method="1000 whole-unit resamples; rule held fixed; conditional descriptive interval")
  }
}
out(do.call(rbind,rows),"review_classification_metrics.csv"); out(do.call(rbind,ci),"review_metric_intervals.csv")

# Exactly vary vegetation, patch size and proximity around the legacy setting without selecting on fire.
sc<-read.csv(tw("data/derived/calibration_all_rules.csv"),check.names=FALSE)
sel<-read_json(tw("data/derived/results_calibration.json"),simplifyVector=TRUE)$selected
ss<-sc[sc$D==sel$D & sc$V==sel$V & sc$R==sel$R,]
ss$interface_km2<-ss$wui_km2-ss$intermix_km2
out(ss[,c("D","V","P","R","A","veg","intermix_km2","interface_km2","wui_km2","wui_buildings")],"review_interface_sensitivity.csv")
# Preserve a separate interface layer for inspection; it is a legacy classification, not ground truth.
cl<-rast(tw("data/derived/wui_class_calibrated_50m.tif")); ir<-ifel(cl==2,1,NA)
writeRaster(ir,tw("data/derived/interface_legacy_50m.tif"),overwrite=TRUE)

# Recompute annual proxy areas across all configured built-share thresholds.
# Observation support is a common domain across years and includes every cell contributing to a neighbourhood.
dom<-rast(tw("data/derived/layers/vegshare_ftm.tif")); w<-circle_w(g,sel$R)
years<-CFG$growth$years
read_dw<-function(y) rast(tw("data/inputs/dynamic_world",sprintf("dw_%d_shares_50m.tif",y)))
obs<-lapply(years,function(y) read_dw(y)[["valid_obs"]])
support<-lapply(c(0,3,5),function(n) {
  valid<-Reduce(`&`,lapply(obs,function(r) !is.na(r) & r>=n))
  # All Bhutan-domain neighbours must pass. Cells outside Bhutan are omitted, as in the original focal mean.
  bad<-ifel(!is.na(dom),ifel(valid,0,1),0)
  values(focal(bad,w,fun="sum",na.rm=TRUE),mat=FALSE)[inside]==0
})
temporal<-list(); classes23<-NULL
for(y in years) {
  r<-read_dw(y); nb<-values(focal(mask(r[["built"]]/100,dom),w,fun="mean",na.rm=TRUE),mat=FALSE)[inside]
  veg<-mask(sum(r[[c("trees","grass","shrub")]])/100,dom)
  vp<-values(100*focal(veg,w,fun="mean",na.rm=TRUE),mat=FALSE)[inside]
  pid<-patches(ifel(veg>=CFG$patch_vegetation_share,1,NA),directions=8,zeroAsNA=TRUE)
  pa<-freq(pid); pd<-values(distance(classify(pid,cbind(pa$value,ifelse(pa$count*km2>=sel$A,1,NA)))),mat=FALSE)[inside]
  for(b in CFG$growth$built_share_grid) {
    cls<-classify_wui(ifelse(nb>b,sel$D+1,0),vp,ifelse(is.na(pd),Inf,pd),sel$D,sel$V,sel$P)
    if(y==2023 && b==.03) classes23<-cls
    for(j in seq_along(support)) {
      ok<-support[[j]] & !is.na(cls)
      temporal[[length(temporal)+1]]<-data.frame(year=y,built_threshold=b,min_mean_obs=c(0,3,5)[j],
        supported_km2=sum(ok)*km2,wui_km2=sum(cls[ok] %in% 1:2)*km2)
    }
  }
  message("Review proxy sensitivity ",y)
}
ts<-do.call(rbind,temporal); out(ts,"review_temporal_sensitivity.csv")
sen<-function(x,y) {ij<-combn(length(x),2); median((y[ij[2,]]-y[ij[1,]])/(x[ij[2,]]-x[ij[1,]]))}
tr<-do.call(rbind,lapply(split(ts,interaction(ts$built_threshold,ts$min_mean_obs,drop=TRUE)),function(x) data.frame(
  built_threshold=x$built_threshold[1],min_mean_obs=x$min_mean_obs[1],supported_km2=x$supported_km2[1],
  sen_km2_year=sen(x$year,x$wui_km2),area_2017=x$wui_km2[1],area_2025=tail(x$wui_km2,1))))
out(tr,"review_temporal_trends.csv")
ref<-values(cl,mat=FALSE)[inside]; cm<-table(reference=factor(ref,1:5),proxy=factor(classes23,1:5))
out(as.data.frame(cm),"review_proxy_2023_confusion.csv")
acc<-data.frame(class=CLASSES,reference_cells=rowSums(cm),proxy_cells=colSums(cm),
  producer_agreement=diag(cm)/rowSums(cm),user_agreement=diag(cm)/colSums(cm))
out(acc,"review_proxy_2023_class_agreement.csv")

# Alternative weighting of the published ordinal exposure ranks.
gt<-read.csv(tw("data/derived/exposure_by_gewog.csv"))
ind<-c("wui_buildings","wui_fire_exposed_buildings","wui_high_susceptibility_buildings","wui_people")
ranks<-sapply(gt[ind],function(x) rank(-x,ties.method="average"))
weights<-rbind(equal=c(.25,.25,.25,.25),population_heavy=c(.1,.1,.1,.7),susceptibility_heavy=c(.1,.1,.7,.1),
  no_population=c(1/3,1/3,1/3,0),buildings_only=c(1,0,0,0))
rr<-do.call(rbind,lapply(seq_len(nrow(weights)),function(j){ score<-as.vector(ranks%*%weights[j,]); data.frame(unit=gt$unit,scenario=rownames(weights)[j],score=score,rank=rank(score,ties.method="min")) }))
out(rr,"review_priority_weights.csv")
profiles<-data.frame(unit=gt$unit,human_exposure_buildings=gt$wui_buildings,modelled_population=gt$wui_people,
  susceptibility_share=gt$wui_high_susceptibility_buildings/pmax(1,gt$wui_buildings),remote_walk_share=gt$wui_remote_buildings/pmax(1,gt$wui_buildings))
out(profiles,"review_management_profiles.csv")
write_json_pretty(list(status="exploratory review audit; independent validation pending",timezone="Asia/Thimphu",
  fire_linkage=list(n_records=nrow(ev),unique_detection_ids=length(unique(fp$detection_id)),provisional_events=nrow(events),
    multisource_events=sum(events$n_sources>1),confirmed_independent_events=NA_integer_,distance_m=1000,local_days=3),
  n_bootstrap_units=length(units),metrics=do.call(rbind,rows),interface_range_km2=range(ss$interface_km2),
  temporal_trends=tr,proxy_class_agreement=acc),tw("data/derived/results_review_audit.json"))
message("Scientific review audit complete. No legacy results replaced.")
