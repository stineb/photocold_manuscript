#############################################
#Aim:comparing the simple LUE, P-model and EC based GPP:
#-->to check if only consider the instanenous environmental vars will result in 
#overestimation of GPP:
##-->need to update the code tomorrrow!
#############################################
library(dplyr)
library(lubridate)
library(ggplot2)
library(tidyr)
library(lme4)
library(tidyverse)
# remotes::install_github("geco-bern/ingestr") #install the package
library(ingestr)
library(rbeni)

#-----------------
#(1) tidy up the data
#load the merged fluxes data and also used the 
#phenophases(SOS and POS) extracted to determine the green-up period  
#-----------------
#--load the merged fluxes data
load.path<-"./data-raw/raw_data/Merged_data/"
load(paste0(load.path,"Merged_Flux_and_VIs.RDA"))
#
df_merge$year<-year(df_merge$date)
df_merge$doy<-yday(df_merge$date)

#--load the phenophases data
phenos.path<-"./data/event_length/"
load(paste0(phenos.path,"df_events_length.RDA"))
#Over_days_length-->days when gpp overestimated 
df_phenos<-df_events_all[,c("sitename","Year","sos","peak","Over_days_length")]
names(df_phenos)<-c("sitename","year","sos","peak","Over_days_length")

#------merge flux data and phenos data------------------------
df_merge<-left_join(df_merge,df_phenos,by=c("sitename","year"))
#only keep the site-year when sos and peak both available
df_final<-df_merge[!is.na(df_merge$sos)&!is.na(df_merge$peak),]

#--------------------------
#(2)start to fit constant LUE model and simple LUE model using lme()
#--------------------------
ddf <- df_final %>% 
  as_tibble() %>%
  # mutate(doy = lubridate::yday(date)) %>% 
  mutate(greenup = ifelse(doy > sos & doy < peak, TRUE, FALSE))
#check the data avaiablilty:
# visdat::vis_miss(ddf, warn_large_data = FALSE)

## Empirical LUE models
# Determine bias of early season bias of empirical LUE models 
# by fitting models outside greenup period.-->
# two LUE model: constant LUE and LUE with VPD and temp as the drivers
ddf <- ddf %>% 
  #the variables of ppfd_fluxnet2015 has some probelm==> using PPFD_IN_fullday_mean_fluxnet2015
  mutate(lue = gpp_obs / (fapar_itpl * PPFD_IN_fullday_mean_fluxnet2015)) %>% 
  mutate(lue = remove_outliers(lue)) #using the functions in the ingestr

###2a).LUE model
##take mean LUE for constant-LUE model
mod_constlue <- ddf %>% 
  filter(!greenup) %>% 
  pull(lue) %>% 
  mean(., na.rm = TRUE)

## LUE as a linear function of temp and vpd
mod_lue_temp_vpd <- lm(lue ~ temp_day_fluxnet2015 + vpd_day_fluxnet2015, 
                       data = ddf %>% 
                         filter(!greenup))
##2b.) add year and elevation mixed effects model
ddf <- ingestr::siteinfo_fluxnet2015 %>%
  select(sitename, elv) %>%
  right_join(ddf, by = "sitename") %>%
  mutate(year = lubridate::year(date))

##remove the na values and infinite data
tmp <- ddf %>% 
  dplyr::filter(!greenup) %>%
  dplyr::filter(PPFD_IN_fullday_mean_fluxnet2015 > 5) %>% 
  dplyr::select(temp_day_fluxnet2015, vpd_day_fluxnet2015, lue, sitename, year) %>%
  drop_na() %>% 
  dplyr::filter(!is.infinite(lue) & !is.nan(lue)) %>% 
  dplyr::filter(!is.infinite(temp_day_fluxnet2015) & !is.nan(temp_day_fluxnet2015)) %>% 
  dplyr::filter(!is.infinite(vpd_day_fluxnet2015) & !is.nan(vpd_day_fluxnet2015)) %>% 
  filter(vpd_day_fluxnet2015 > 0 & lue > 0) %>% 
  droplevels()

mod_lmer <- lmer(lue ~ temp_day_fluxnet2015+log(vpd_day_fluxnet2015) + (1|sitename),
                   data=tmp)

#2c).merge the data
ddf <- ddf %>% 
  filter(sitename!="CN-Qia")%>%  ## since mod_lmer do not include the CN-Qia site
  #==>glmer prediction has some probelm
  mutate(lue_temp_vpd = predict(mod_lue_temp_vpd,newdata = .))%>%
  mutate(gpp_temp_vpd = lue_temp_vpd * fapar_itpl * PPFD_IN_fullday_mean_fluxnet2015) %>%
  mutate(lue_lmer = predict(mod_lmer, newdata = .)) %>%
  mutate(gpp_lmer = lue_lmer * fapar_itpl * PPFD_IN_fullday_mean_fluxnet2015) %>%
  mutate(gpp_lue_const = mod_constlue * fapar_itpl * PPFD_IN_fullday_mean_fluxnet2015)

#--------------------------
#(3)compare the models
#--------------------------
#change the names of modelled GPP:
ddf<-ddf %>%
  mutate(gpp_pmodel=gpp_mod_FULL,
         gpp_mod_FULL=NULL)
## P-model
ddf %>% 
  analyse_modobs2("gpp_pmodel", "gpp_obs", type = "hex")

## constant LUE model
ddf %>% 
  analyse_modobs2("gpp_lue_const", "gpp_obs", type = "hex")

## LUE ~ temp + VPD model:lm
ddf %>% 
  analyse_modobs2("gpp_temp_vpd", "gpp_obs", type = "hex")

## LUE ~ temp + VPD model:glmer
ddf %>% 
  filter(!is.nan(gpp_lmer) & !is.infinite(gpp_lmer))%>%
  analyse_modobs2("gpp_lmer", "gpp_obs", type = "hex")

#--------------------------
#(4)Mean seasonal cycle
#--------------------------
df_meandoy <- ddf %>% 
  group_by(sitename, doy) %>% 
  summarise(across(starts_with("gpp_"), mean, na.rm = TRUE))

##plot by site:
df_meandoy %>% 
  filter(!is.nan(gpp_lmer) & !is.infinite(gpp_lmer))%>% ##this filter is important
  pivot_longer(c(gpp_obs, gpp_pmodel, gpp_lue_const,gpp_temp_vpd,gpp_lmer), names_to = "model", values_to = "gpp") %>% 
  #fct_relevel: in tidyverse package
  mutate(model = fct_relevel(model, "gpp_obs", "gpp_pmodel", "gpp_lue_const","gpp_temp_vpd","gpp_lmer")) %>% 
  dplyr::filter((model %in% c( "gpp_obs", "gpp_pmodel","gpp_temp_vpd","gpp_lmer"))) %>% 
  # filter(sitename=="DE-Tha")%>%
  ggplot() +
  # geom_ribbon(
  #   aes(x = doy, ymin = obs_min, ymax = obs_max), 
  #   fill = "black", 
  #   alpha = 0.2
  #   ) +
  geom_line(aes(x = doy, y = gpp, color = model), size = 0.4) +
  labs(y = expression( paste("Simulated GPP (g C m"^-2, " d"^-1, ")" ) ), 
       x = "DOY") +
  facet_wrap( ~sitename, ncol = 3 ) +    # , labeller = labeller(climatezone = list_rosetta)
  theme_gray() +
  theme(legend.position = "bottom") +
  scale_color_manual(
    name="Model: ",
    values=c("black", "red", "royalblue", "darkgoldenrod", "springgreen", "orchid4")
  )

ggsave("./manuscript/test_files/gpp_meandoy.pdf", height = 25, width = 8)

##############################
## Normalise to peak season
##############################
norm_to_peak <- function(df, mod, obs){
  
  q75_obs <- quantile(df[[obs]], probs = 0.75, na.rm = TRUE)
  q75_mod <- quantile(df[[mod]], probs = 0.75, na.rm = TRUE)
  
  ## normalise mod
  df[[mod]] <- df[[mod]] * 
    mean(df[[obs]][df[[obs]]>q75_obs], na.rm = TRUE) / 
    mean(df[[mod]][df[[obs]]>q75_obs], na.rm = TRUE)
  
  return(df)
}

ddf_norm <- ddf %>% 
  group_by(sitename) %>% 
  nest() %>% 
  mutate(data = purrr::map(data, ~norm_to_peak(., "gpp_pmodel", "gpp_obs"))) %>% 
  # mutate(data = purrr::map(data, ~norm_to_peak(., "gpp_bess", "gpp_obs"))) %>% 
  # mutate(data = purrr::map(data, ~norm_to_peak(., "gpp_rf", "gpp_obs"))) %>% 
  # mutate(data = purrr::map(data, ~norm_to_peak(., "gpp_bf", "gpp_obs"))) %>% 
  mutate(data = purrr::map(data, ~norm_to_peak(., "gpp_lue_const", "gpp_obs"))) %>% 
  mutate(data = purrr::map(data, ~norm_to_peak(., "gpp_temp_vpd", "gpp_obs"))) %>% 
  mutate(data = purrr::map(data, ~norm_to_peak(., "gpp_lmer", "gpp_obs"))) %>% 
  unnest(data)

### Plot normalised by site
df_meandoy_norm <- ddf_norm %>% 
  group_by(sitename, doy) %>% 
  summarise(across(starts_with("gpp_"), mean, na.rm = TRUE))

df_meandoy_norm %>% 
  filter(!is.nan(gpp_lmer) & !is.infinite(gpp_lmer))%>% ##this filter is important
  pivot_longer(c(gpp_obs, gpp_pmodel, gpp_lue_const, gpp_temp_vpd,gpp_lmer), names_to = "model", values_to = "gpp") %>%
  mutate(model = fct_relevel(model, "gpp_obs", "gpp_pmodel", "gpp_lue_const", "gpp_temp_vpd","gpp_lmer")) %>%
  dplyr::filter((model %in% c( "gpp_obs", "gpp_pmodel", "gpp_temp_vpd","gpp_lmer"))) %>% 
  # pivot_longer(c(gpp_obs, gpp_pmodel, gpp_lue_const, gpp_temp_vpd), names_to = "model", values_to = "gpp") %>% 
  # mutate(model = fct_relevel(model, "gpp_obs", "gpp_pmodel", "gpp_lue_const", "gpp_temp_vpd")) %>% 
  # dplyr::filter((model %in% c( "gpp_obs", "gpp_pmodel", "gpp_temp_vpd"))) %>% 
  ggplot() +
  # geom_ribbon(
  #   aes(x = doy, ymin = obs_min, ymax = obs_max), 
  #   fill = "black", 
  #   alpha = 0.2
  #   ) +
  geom_line(aes(x = doy, y = gpp, color = model), size = 0.4) +
  labs(y = expression( paste("Simulated GPP (g C m"^-2, " d"^-1, ")" ) ), 
       x = "DOY") +
  facet_wrap( ~sitename, ncol = 3, scales = "free_y" ) +
  theme_gray() +
  theme(legend.position = "bottom") +
  scale_color_manual(
    name="Model: ",
    values=c("black", "red", "royalblue", "darkgoldenrod", "springgreen", "orchid4")
  )
ggsave("./manuscript/test_files/gpp_meandoy_norm.pdf", height = 25, width = 8)
