##---------------------------------------
#Aim: To compare the parameters among different groups(e.g.PFTs) after calibrating
#parameters for each site
##---------------------------------------
library(dplyr)
library(devtools)
devtools::load_all("D:/Github/rbeni/")
# install_github("stineb/rbeni")
library(rbeni) #-->make the evaluation plot
library(tidyverse)
library(cowplot)
library(grid)
library(ggpubr)
library(lubridate)
#---------------------------
#(1)load the calibrated parameters for each site
#---------------------------
load(paste0("./data/model_parameters/parameters_MAE_newfT/","optim_par_run5000_eachsite_new.rds"))
#merge the parameters:
merge_pars<-c()
sites<-names(par_mutisites)
for(i in 1:length(par_mutisites)){
  temp<-t(as.data.frame(par_mutisites[i]))
  merge_pars<-rbind(merge_pars,temp)
}
pars_final<-as.data.frame(t(merge_pars))
names(pars_final)<-sites
#change the parameters name:
rownames(pars_final)<-c("tau","X0","Smax","k")

#----------------------------
#(2)load original data(meteos, gpp..)
#----------------------------
#load the data uploaded by Koen
df_recent <- readRDS(paste0("./data-raw/raw_data/P_model_output/model_data.rds")) %>%
  mutate(
    year = format(date, "%Y")
  ) %>%
  na.omit()

#load the PFTs information:
#load the modis data-->tidy from Beni
#read_rds from tidyverse
load(paste0("./data-raw/raw_data/sites_info/","Pre_selected_sites_info.RDA"))
sites.info<-df_sites_sel

#----
#merge the data
#-----
df_merge<-left_join(df_recent,sites.info,by="sitename")
df_merge$year<-as.numeric(df_merge$year)
#load the data Beni sent me before:
df_old<-read.csv(file=paste0("./data-raw/raw_data/Data_sent_by_Beni/","ddf_fluxnet2015_pmodel_with_forcings_stocker19gmd.csv"))
df_old<-df_old %>%
  mutate(date=lubridate::mdy(date),
         year=lubridate::year(date)) %>%
  na.omit(gpp_obs)
#----
#merge data:
#----
df_merge_new<-left_join(df_merge,df_old,by=c("sitename", "date", "year"))
#update in Nov,2022-->also add the green-up information:
phenology.path<-"./data/event_length/"
load(paste0(phenology.path,"df_events_length.RDA"))
df.pheno<-df_events_all%>%
  select(sitename,Year,sos,peak)%>%
  mutate(year=Year,Year=NULL)
#
df_merge_new<-left_join(df_merge_new,df.pheno)

#-----------
#summarize the meteos for each site
#-----------
#focus on the data in whole year, green-up period,and winter(-60:sos)
df_merge_new<-df_merge_new%>%
  mutate(doy=yday(date))%>%
  mutate(greenup=ifelse(doy>=sos & doy<=peak,"greenup","Notgreenup"))

meteo_sum_fun<-function(df,sel_period){
  # df<-df_merge_new
  # sel_period<-"greenup"
  
  #
  if(sel_period=="greenup"){
    df_merge_new<-df %>%
      filter(greenup=="greenup")
  }
  if(sel_period=="winter"){
    df_merge_new<-df %>%
      filter(doy>=c(sos-60) & doy<=sos)
  }
  if(sel_period=="year"){
    df_merge_new<-df
  }
  if(sel_period=="winter_to_greenup"){
    df_merge_new<-df %>%
      filter(doy>=c(sos-60) & doy<=peak)
  }
  
  
  df_sum_yearly_1<-df_merge_new %>%
    group_by(sitename,year) %>%
    dplyr::summarise(temp=mean(temp),
                     prec=sum(prec),
                     vpd=mean(vpd),
                     ppdf=mean(ppfd),
                     elv=mean(elv),
                     tmin=mean(tmin),
                     tmax=mean(tmax),
                     fapar_itpl=mean(fapar_itpl),
                     fapar_spl=mean(fapar_spl)
    )
  df_sum_yearly_2<-df_merge_new %>%
    group_by(sitename,year) %>%
    dplyr::summarise(lon=unique(lon),
                     lat=unique(lat),
                     classid=unique(classid),
                     koeppen_code=unique(koeppen_code))
  df_sum_yearly<-left_join(df_sum_yearly_1,df_sum_yearly_2)
  
  #---
  #summary site-years for site
  #---
  df_sum_1<-df_sum_yearly %>%
    group_by(sitename) %>%
    summarise_at(vars(temp:fapar_spl),mean,na.rm=T)
  df_sum_2<-df_sum_yearly %>%
    group_by(sitename) %>%
    dplyr::summarise(lon=unique(lon),
                     lat=unique(lat),
                     classid=unique(classid),
                     koeppen_code=unique(koeppen_code))
  df_sum<-left_join(df_sum_1,df_sum_2)
  
  ##-----------------------
  #(3) compare the parameter difference in differnt group
  ##----------------------
  df_sum$Clim.PFTs<-paste0(df_sum$koeppen_code,"-",df_sum$classid)
  #only target the sites we used for the analysis:
  ##---------------------
  #A.load the event_length data-->the sites we were used
  #---------------------
  load.path<-"./data/event_length/"
  load(paste0(load.path,"df_events_length.RDA"))
  #
  used_sites<-unique(df_events_all$sitename)
  
  #-----select the data for thoses used sites----
  #delete the sites do not used:
  df_final<-df_sum %>%
    filter(sitename %in% used_sites)
  return(df_final)
}
#
df_year<-meteo_sum_fun(df_merge_new,"year")
df_greenup<-meteo_sum_fun(df_merge_new,"greenup")
df_winter<-meteo_sum_fun(df_merge_new,"winter")
df_winter_to_greenup<-meteo_sum_fun(df_merge_new,"winter_to_greenup")
#--------------------------
#(4)plotting:
#--------------------------
#first merge the parameters with meteos:
pars_final<-as.data.frame(t(pars_final))
pars_final$sitename<-rownames(pars_final)

#merge-->update in Nov,2022-->changing the df_final(df_year;df_greenup;df_winter) manually right now
df_final<-df_winter_to_greenup
df_final_new<-left_join(df_final,pars_final,by="sitename")
#---
#check the variables distribution and boxplots
#---
vars.names<-c("tau","X0","Smax","k")
for (i in 1:length(vars.names)) {
  hist(as.numeric(unlist(df_final_new[,vars.names[i]])),xlab = vars.names[i])
}

##----------boxplot---------------------
#a. first for site-level parameters
data_sel_sites<-df_final_new %>%
  dplyr::select(sitename,classid,tau:k)%>%
  pivot_longer(c(tau:k),names_to = "parameter",values_to = "parameter_value")
#only focus on the tau,X0,Smax
data_sel_sites<-data_sel_sites %>%
  filter(parameter %in% c("tau","X0","Smax"))%>%
  mutate(PFT=classid,
         classid=NULL)
data_sel_sites$flag=rep("site",nrow(data_sel_sites))
#
data_sel_sites$parameter<-factor(data_sel_sites$parameter,
                                 levels = c("tau","X0","Smax"))
#-----------
#b.also load the parameters for diff PFTs:
# load(paste0("./data/model_parameters/parameters_MAE_newfT/","optim_par_run5000_PFTs.rds"))
load(paste0("./data/model_parameters/parameters_MAE_newfT/","optim_par_run5000_PFTs_with_newMF_paras.rds"))
paras_PFTs<-data.frame(DBF=par_PFTs$DBF,
                       MF=par_PFTs$MF,
                       EN=par_PFTs$ENF)
paras_PFTs<-as.data.frame(t(paras_PFTs))
paras_PFTs$PFT<-c("DBF","MF","ENF")
#also change the parameters names:
names(paras_PFTs)<-c("tau","X0","Smax","k","PFT")
#
data_sel_PFTs<-paras_PFTs %>%
  dplyr::select(tau:Smax,PFT)%>%
  pivot_longer(c(tau,X0,Smax),names_to = "parameter",values_to = "parameter_value")
data_sel_PFTs$flag=rep("PFT",nrow(data_sel_PFTs))
#
data_sel_PFTs$parameter<-factor(data_sel_PFTs$parameter,
                                levels = c("tau","X0","Smax"))
#c.load the parameters for diff Clim-PFTs:
load(paste0("./data/model_parameters/parameters_MAE_newfT/","optim_par_run5000_Clim_andPFTs.rds"))
#
paras_Clim_PFTs<-c()
N<-length(names(par_Clim_PFTs))
for(i in 1:N){
  temp<-t(as.data.frame(par_Clim_PFTs[i]))
  paras_Clim_PFTs<-rbind(paras_Clim_PFTs,temp)
}
paras_Clim_PFTs<-as.data.frame(paras_Clim_PFTs)
names(paras_Clim_PFTs)<-c("tau","X0","Smax","k")
#
paras_Clim_PFTs$Clim_PFTs<-names(par_Clim_PFTs)
#
data_sel_Clim_PFTs<-paras_Clim_PFTs %>%
  dplyr::select(tau:Smax,Clim_PFTs)%>%
  pivot_longer(c(tau,X0,Smax),names_to = "parameter",values_to = "parameter_value")
data_sel_Clim_PFTs$flag=rep("Clim-PFT",nrow(data_sel_Clim_PFTs))

#########################
#merge site and PFTs data
data_sel_final<-bind_rows(data_sel_sites,data_sel_PFTs)
data_sel_final<-bind_rows(data_sel_final,data_sel_Clim_PFTs)
  
#box plot with gitter 
data_sel_final$PFT<-factor(data_sel_final$PFT,levels = c("DBF","MF","ENF"))
##parameters distributions of different sites
#
# devtools::install_github("zeehio/facetscales")
# library(facetscales)
# scales_y<-list(
#   "a"=scale_y_continuous(limits = c(-40,25)),
#   "b"=scale_y_continuous(limits = c(-5,25)),
#   "c"=scale_y_continuous(limits = c(-0,200)),
#   "d"=scale_y_continuous(limits = c(-5,20)),
#   "k"=scale_y_continuous(limits = c(-10,15))
# )

data_sel_final$PFT<-factor(data_sel_final$PFT,levels = c("DBF","MF","ENF"))
data_sel_final$parameter<-factor(data_sel_final$parameter,levels = c("tau","X0","Smax"))

###plot part 1:
my_labeller<-as_labeller(c(tau="tau~(day)",X0="X[0]~('°C')",Smax="S[max]~('°C')"),default = label_parsed) #change the label of facet
para_sites<-ggplot(data=data_sel_final[data_sel_final$flag=="site",],
                   aes(x=parameter,y=parameter_value,fill=PFT,col=PFT))+
  geom_point(position = position_jitterdodge())+
  geom_boxplot(alpha=0.6)+
  xlab("")+
  facet_wrap(~parameter,scales = "free",ncol = 3,labeller = my_labeller)+
  xlab("Parameters")+
  ylab("")+
  theme_bw()+
  # theme(legend.position = c(0.75,0.18),
  theme(
        legend.background = element_blank(),
        legend.title = element_text(size=18),
        legend.text = element_text(size=16),
        axis.title = element_text(size=18),
        axis.text.y = element_text(size=16),
        axis.text.x = element_blank(),
        axis.ticks.x = element_blank(),
        strip.text.x = element_text(size = 18)) ##change the facet label size
##add the a,b,c indicate the panels:
dat_text<-data.frame(label=c("a","b","c"),parameter=c("tau","X0","Smax"),
                     PFT=rep("DBF",3),
                     x=rep(0.5,3),y=c(25,3,25))
dat_text$parameter<-factor(dat_text$parameter,levels = c("tau","X0","Smax"))
para_sites<-para_sites+geom_text(
  data=dat_text,
  size=6,col="black",
  mapping = aes(x=x,y=y,label=label)
)
#change the color-blind friendly color==>refer the package colorspace
#refer:https://stackoverflow.com/questions/57153428/r-plot-color-combinations-that-are-colorblind-accessible
library(colorspace)
# mycolors<-rev(sequential_hcl(7,palette = "Viridis")[c(1,3,5)])
para_sites<-para_sites+
  # scale_fill_discrete_sequential(palette = "Viridis",alpha=0.5)+
  # scale_color_discrete_sequential(palette = "Viridis",alpha = 0.5)
  khroma::scale_color_highcontrast(aesthetics = "fill")+
  khroma::scale_color_highcontrast(aesthetics = "color")
  # scale_fill_manual(values = c("DBF"=adjustcolor("orange",alpha.f =0.2),
  #       "MF"=adjustcolor("cyan",alpha.f =0.2),"ENF"=adjustcolor("magenta",alpha.f =0.2)))+
  # scale_color_manual(values = c("DBF"="orange","MF"="cyan2","ENF"="magenta3"))
#---------------------------------------------
#:
tag_facet <- function(p, open = "", close = "", tag_pool = letters, x = -Inf, y = Inf, 
                      hjust = "", vjust = "", fontface = 2, family = "", ...) {
  
  # p<-para_sites
  # x=paras_PFTs_new$x
  # y=paras_PFTs_new$parameter_value
  # open=""
  # close=""
  # tag_pool=paras_PFTs_new$label
  
  gb <- ggplot_build(p)
  lay <- gb$layout$layout
  tags <- cbind(lay, label = paste0(open, tag_pool[lay$PANEL], close), x = x, y = y)
  p + geom_text(data = tags, aes_string(x = "x", y = "y", label = "label"), ..., hjust = hjust, 
                vjust = vjust, fontface = fontface, family = family, inherit.aes = FALSE) 
}
library(egg)

##add the PFTs parameters onto each panel:
paras_PFTs_new<-data_sel_final[data_sel_final$flag=="PFT",-1]
paras_PFTs_new$x<-rep(NA,nrow(paras_PFTs_new))
paras_PFTs_new[paras_PFTs_new$PFT=="MF",]$x<-1
paras_PFTs_new[paras_PFTs_new$PFT=="DBF",]$x<-0.75
paras_PFTs_new[paras_PFTs_new$PFT=="ENF",]$x<-1.25
##
paras_PFTs_new$label<-rep("*",nrow(paras_PFTs_new))
# paras_PFTs_new$col<-c(rep("goldenrod",3),rep("cyan2",3),rep("magenta3",3))
paras_PFTs_new$col<-c(rep("darkblue",3),rep("orange",3),rep("tomato",3))

#
# paras_PFTs_new$PFT<-factor(paras_PFTs_new$PFT,levels = c("DBF","MF","ENF"))
# paras_PFTs_new$parameter<-factor(paras_PFTs_new$parameter,levels = c("tau","X0","Smax"))
paras_boxplot<-tag_facet(para_sites,x=paras_PFTs_new$x,y=paras_PFTs_new$parameter_value,
                         #here I add 1 for y axis since there parameters for PFTs did not display properly
                           tag_pool = paras_PFTs_new$label,size=12,col=paras_PFTs_new$col)
#save the plot
save.path<-"./manuscript/figures/"
ggsave(paste0(save.path,"Figure6_parameters_boxplot.png"),paras_boxplot,height = 5,width = 8)

###plot part 2:
#----------------scatter plot------------------
#environmental drivers vs parameters
library(ggforce)
library(ggrepel)
plot_paras<-function(df_meteo,df_paras,Env_var,para,do_legend){
  # df_meteo<-df_final_new
  # df_paras<-data_sel_final
  # Env_var<-"tmin"
  # para<-"tau"
  # do_legend=FALSE
  # for example: Tmean vs tau
  #I.site-level
  df_site_level<-df_meteo %>%
    dplyr::select(sitename,classid,koeppen_code,Clim.PFTs,para,tmin,temp)
  names(df_site_level)<-c("sitename","PFT","Clim.","Clim.PFTs","para","tmin","tmean")
  #
  t_pos<-match(Env_var,names(df_site_level))
  df_site_level_new<-df_site_level
  names(df_site_level_new)[t_pos]<-"Env_var"
  
  #III.PFT level---
  df_PFT_level<-df_site_level%>%
    mutate(PFT=factor(PFT,levels = c("DBF","MF","ENF")))%>%
    group_by(PFT)%>%
    dplyr::summarise(tmin=mean(tmin,na.rm=T),
              tmean=mean(tmean,na.rm=T))
  par_PFT_level<-df_paras[df_paras$flag=="PFT",] %>%
    mutate(sitename=NULL,Clim_PFTs=NULL,flag=NULL)%>%
    filter(parameter==para)
  par_PFT_level<-par_PFT_level[,-1]
  names(par_PFT_level)<-c("para","PFT")
  #
  df_PFT_level_new<-left_join(df_PFT_level,par_PFT_level)
  #
  t_pos<-match(Env_var,names(df_PFT_level_new))
  names(df_PFT_level_new)[t_pos]<-"Env_var"
  
  ##----plotting----##
  library(ggpmisc)  
  # library(ggpubr)
  #linear regression:
  #----DBF------
  lm_DBF<-lm(data=df_site_level_new[df_site_level_new$PFT=='DBF',],
     para~Env_var)
  stat_lm_DBF<-summary(lm_DBF)
  stat_DBF_label<-data.frame(r.squared=round(stat_lm_DBF$r.squared,2),
                         p.value=round(coef(stat_lm_DBF)[2,4],4))
  #----Dfc-ENF-----
  lm_Dfc_ENF<-lm(data=df_site_level_new[df_site_level_new$Clim.PFTs=='Dfc-ENF',],
             para~Env_var)
  stat_lm_Dfc_ENF<-summary(lm_Dfc_ENF)
  stat_Dfc_ENF_label<-data.frame(r.squared=round(stat_lm_Dfc_ENF$r.squared,2),
                         p.value=round(coef(stat_lm_Dfc_ENF)[2,4],4))
  
  pars_final<-ggplot(data=df_site_level_new,aes(x=Env_var,y=para))+
    geom_point(aes(col=PFT),size=3)+
    # scale_color_discrete_sequential(palette = "Viridis")+
    geom_text_repel(aes(label=sitename),size=5)+
    #!update in Jan,2023: stat_poly_line(data=df_site_level_new[df_site_level_new$PFT=='DBF',],
    #             aes(x=Env_var,y=para,col=PFT),
    #             fill=adjustcolor("goldenrod1"),method = "lm",formula = y ~ x,lty=2)+
    # stat_poly_eq(data=df_site_level_new[df_site_level_new$PFT=='DBF',],
    #                aes(x=Env_var,y=para,col=PFT,
    #                    label = paste(
    #                                  # after_stat(grp.label), "*\"：\"*",
    #                                  # after_stat(eq.label), "*\", \"*",
    #                                  after_stat(rr.label), 
    #                                  after_stat(p.value.label),
    #                                  sep = "*\", \"*"),
    #                    label.x=0.5,label.y="bottom"))+
    ##update in Nov,2022-->remove the circle
    # ggforce::geom_mark_ellipse(data=df_site_level_new[df_site_level_new$PFT=='DBF',],
    #     aes(x=Env_var,y=para,label=PFT,group=PFT,col=PFT),label.fill = "goldenrod1",
    #     con.border = "one",con.cap = 0,con.size = 1.1,con.colour = "goldenrod1",
    #     con.arrow = grid::arrow(angle=30,ends = "last",length = unit(0.1,"inches")))+  ##DBF
    #!update in Jan,2023:stat_poly_line(data=df_site_level_new[df_site_level_new$Clim.PFTs=='Dfc-ENF',],
    #       aes(x=Env_var,y=para,col=PFT),fill=adjustcolor("magenta1"),
    #       method = "lm",formula = y ~ x,lty=2)+
    # stat_poly_eq(data=df_site_level_new[df_site_level_new$Clim.PFTs=='Dfc-ENF',],
    #                  aes(x=Env_var,y=para,col=PFT,
    #                     label = paste(
    #                       after_stat(rr.label), 
    #                       after_stat(p.value.label),
    #                       sep = "*\", \"*"),
    #                 label.x=0.5,label.y="bottom"))+
    ##update in Nov,2022-->remove the circle
    # ggforce::geom_mark_ellipse(data=df_site_level_new[df_site_level_new$Clim.PFTs=="Dfc-ENF",],
    #     aes(x=Env_var,y=para,label=Clim.PFTs,group=Clim.PFTs,col=PFT),label.fill = "magenta1",
    #     con.border = "one",con.cap = 0,con.size = 1.1,con.colour = "magenta1",
    #     con.arrow = grid::arrow(angle=30,ends = "last",length = unit(0.1,"inches")))+  ##Dfc-ENF
    # scale_color_manual(values = c("DBF"="orange","MF"="cyan","ENF"="magenta"))+
    khroma::scale_color_highcontrast(aesthetics = "color")+
    xlab(paste0(Env_var," (°C)"))+
    ylab(paste0(para," (°C)"))+
    xlim(-10,15)+
    theme(
      legend.text = element_text(size=22),
      legend.position = c(0.15,0.8),
      legend.background = element_rect(fill = "white"),
      legend.key.size = unit(2, 'lines'),
      axis.title = element_text(size=26),
      axis.text = element_text(size = 22),
      text = element_text(size=24),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      panel.background = element_rect(colour ="grey",fill="white")
    )
  if(para=="tau"){
    pars_final<-pars_final+
    stat_poly_line(data=df_site_level_new[df_site_level_new$PFT=='DBF',],
                     aes(x=Env_var,y=para,col=PFT),
                     fill=adjustcolor("steelblue2"),method = "lm",formula = y ~ x,lty=2,
                     show_guide=FALSE)+
    stat_poly_line(data=df_site_level_new[df_site_level_new$Clim.PFTs=='Dfc-ENF',],
                     aes(x=Env_var,y=para,col=PFT),fill=adjustcolor("gold"),
                     method = "lm",formula = y ~ x,lty=2,
                     show_guide = FALSE)+
    annotate(geom = "text",x=10.1,y=24,label = paste0("italic(R) ^ 2 == ",
                      stat_DBF_label$r.squared),parse=TRUE,col="steelblue4",size=7)+
    annotate(geom = "text",x=14,y=24,label = paste0("italic(p) ==",
                      round(stat_DBF_label$p.value,2)),parse=TRUE,col="steelblue4",size=7)+
    annotate(geom = "text",x=10.1,y=22,label = paste0("italic(R) ^ 2 == ",
                      stat_Dfc_ENF_label$r.squared),parse=TRUE,col="goldenrod3",size=7)+
    annotate(geom = "text",x=14,y=22,label = paste0("italic(p) == ",
                     round(stat_Dfc_ENF_label$p.value,2)),parse=TRUE,col="goldenrod3",size=7)
  }
  if(para=="X0"){
    pars_final<-pars_final+
      annotate(geom = "text",x=10.1,y=5,label = paste0("italic(R) ^ 2 == ",
                     stat_DBF_label$r.squared),parse=TRUE,col="steelblue4",size=7)+
      annotate(geom = "text",x=14,y=5,label = paste0("italic(p) ==",
                     round(stat_DBF_label$p.value,2)),parse=TRUE,col="steelblue4",size=7)+
      annotate(geom = "text",x=10.1,y=4,label = paste0("italic(R) ^ 2 == ",
                     stat_Dfc_ENF_label$r.squared),parse=TRUE,col="goldenrod3",size=7)+
      annotate(geom = "text",x=14,y=4,label = paste0("italic(p) == ",
                     round(stat_Dfc_ENF_label$p.value,2)),parse=TRUE,col="goldenrod3",size=7)
  }
  if(para=="Smax"){
    pars_final<-pars_final+
      # stat_poly_line(data=df_site_level_new[df_site_level_new$PFT=='DBF',],
      #                aes(x=Env_var,y=para,col=PFT),
      #                fill=adjustcolor("goldenrod1"),method = "lm",formula = y ~ x,lty=2,
      #                show_guide=FALSE)+
      # stat_poly_line(data=df_site_level_new[df_site_level_new$Clim.PFTs=='Dfc-ENF',],
      #                aes(x=Env_var,y=para,col=PFT),fill=adjustcolor("magenta1"),
      #                method = "lm",formula = y ~ x,lty=2,
      #                show_guide = FALSE)+
      annotate(geom = "text",x=10.1,y=24,label = paste0("italic(R) ^ 2 == ",
                     stat_DBF_label$r.squared),parse=TRUE,col="steelblue4",size=7)+
      annotate(geom = "text",x=14,y=24,label = paste0("italic(p) ==",
                     round(stat_DBF_label$p.value,2)),parse=TRUE,col="steelblue4",size=7)+
      annotate(geom = "text",x=10.1,y=22.5,label = paste0("italic(R) ^ 2 == ",
                     stat_Dfc_ENF_label$r.squared),parse=TRUE,col="goldenrod3",size=7)+
      annotate(geom = "text",x=14,y=22.5,label = paste0("italic(p) == ",
                     round(stat_Dfc_ENF_label$p.value,2)),parse=TRUE,col="goldenrod3",size=7)
  }
  
  if(do_legend==FALSE){
    pars_final<-pars_final+
      theme(legend.position = "none")
  }
  #
  return(pars_final)
}
############
# df_meteo<-df_final_new
# df_paras<-data_sel_final
# Env_var<-"tmin"
# para<-"a1"
# do_legend=FALSE

p_tmin_tau<-plot_paras(df_meteo = df_final_new,df_paras = data_sel_final,Env_var = "tmin",
           para = "tau",TRUE)
p_tmin_X0<-plot_paras(df_meteo = df_final_new,df_paras = data_sel_final,Env_var = "tmin",
                      para = "X0",FALSE)  
p_tmin_Smax<-plot_paras(df_meteo = df_final_new,df_paras = data_sel_final,Env_var = "tmin",
                      para = "Smax",FALSE)

#change the x labels:
p_tmin_tau<-p_tmin_tau+
  # xlab(expression("T"[min]*" (°C)"))+ylab(expression(tau*""))+
  xlab("")+ylab(expression(tau*""))
p_tmin_X0<-p_tmin_X0+
  xlab(expression("T"[min]*" (°C)"))+ylab(expression(X[0]*" (°C)"))+
  xlab("")+ylab(expression(X[0]*" (°C)"))
p_tmin_Smax<-p_tmin_Smax+
  xlab(expression("T"[min]*" (°C)"))+ylab(expression(S[max]*" (°C)"))

#merge the plots:
paras_range<-cowplot::plot_grid(p_tmin_tau,p_tmin_X0,p_tmin_Smax,nrow=3,
          ncol = 1,labels = "auto",label_size = 20,align = "hv")
######save the plot###########
save.path<-"./manuscript/figures/"
ggsave(paste0(save.path,"Figure7_winter_to_geenup_parameters_ranges.png"),paras_range,height = 21,width =10)

#############################additional code ###########################
#----
#check the paraters difference among different groups
#----
library(ggpubr)
library(cowplot)
check_groups<-function(df,par_name){
  # df<-df_final_new
  # par_name<-"a1"

  df_t<-df %>%
    select(sitename,classid,koeppen_code,Clim.PFTs,par_name)
  names(df_t)<-c("sitename","classid","koeppen_code","Clim.PFTs","par")
  #for different PFTs
  p_PFTs<-ggplot(data=df_t,aes(x=par,color=classid,fill=classid))+
    geom_histogram(aes(y=..density..,),position = "identity",binwidth = 1,alpha=0.5)+
    geom_density(alpha=.2)+
    xlab(par_name)
  #for different Clim.
  p_Clim<-ggplot(data=df_t,aes(x=par,color=koeppen_code,fill=koeppen_code))+
    geom_histogram(aes(y=..density..,),position = "identity",binwidth = 1,alpha=0.5)+
    geom_density(alpha=.2)+
    xlab(par_name)
  #for different Clim.-PFTs
  p_Clim.PFTs<-ggplot(data=df_t,aes(x=par,color=Clim.PFTs,fill=Clim.PFTs))+
    geom_histogram(aes(y=..density..,),position = "identity",binwidth = 1,alpha=0.5)+
    xlab(par_name)
  # geom_density(alpha=.2)
  #
  p_merge<-plot_grid(p_PFTs,p_Clim,p_Clim.PFTs)
  return(p_merge)
}
##
check_groups(df_final_new,"a1")
check_groups(df_final_new,"b1")
check_groups(df_final_new,"a2")
check_groups(df_final_new,"b2")
check_groups(df_final_new,"e")
check_groups(df_final_new,"f")
check_groups(df_final_new,"k")

#----
#check environmental drivers relationship between parameters
#----
check_relation<-function(df,par_name){
  # df<-df_final_new
  # par_name<-"a1"

  df_t<-df %>%
    select(sitename:fapar_spl,classid,koeppen_code,Clim.PFTs,par_name)
  names(df_t)<-c("sitename","temp","prec","vpd","ppdf","elv",
                 "tmin","tmax","fapar_itpl","fapar_spl",
                 "classid","koeppen_code","Clim.PFTs","par")
  #
  p_ta<-ggplot(data=df_t,aes(x=temp,y=par,color=classid))+
    geom_point()+
    xlab("ta")+
    ylab(par_name)
  #
  p_prec<-ggplot(data=df_t,aes(x=prec,y=par,color=classid))+
    geom_point()+
    xlab("prec")+
    ylab(par_name)
  p_vpd<-ggplot(data=df_t,aes(x=vpd,y=par,color=classid))+
    geom_point()+
    xlab("vpd")+
    ylab(par_name)
  p_ppfd<-ggplot(data=df_t,aes(x=ppdf,y=par,color=classid))+
    geom_point()+
    xlab("ppfd")+
    ylab(par_name)
  p_tmin<-ggplot(data=df_t,aes(x=tmin,y=par,color=classid))+
    geom_point()+
    xlab("tmin")+
    ylab(par_name)
  p_tmax<-ggplot(data=df_t,aes(x=tmax,y=par,color=classid))+
    geom_point()+
    xlab("tmax")+
    ylab(par_name)
  p_fapar<-ggplot(data=df_t,aes(x=fapar_itpl,y=par,color=classid))+
    geom_point()+
    xlab("fapar_itpl")+
    ylab(par_name)
    #
  p_merge<-plot_grid(p_ta,p_prec,p_vpd,
                     p_ppfd,p_tmin,p_fapar,nrow = 2,align = "hv")
  return(p_merge)
}

#
check_relation(df_final_new,"a1")
check_relation(df_final_new,"b1")
check_relation(df_final_new,"a2")
check_relation(df_final_new,"b2")
check_relation(df_final_new,"e")
check_relation(df_final_new,"f")
check_relation(df_final_new,"k")

