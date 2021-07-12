function [reject_ind_yr_val,reject_pres_val,ini_rejuv_cost,rejuv_ind_yr_val,rejuv_pres_val,total_sys_replace,total_rejuv_cost] = test()
%initialize variables
a = .25;
reject_rate = .45;
accept_rate = .55;
pot_candidates = 100000;
mean_length = 350;
replacement_cost = 30;
replacement_rate = [.1,.23,.23,.22,.22];
reject_ind_yr_val = zeros(1,5);
reject_pres_val = 0;
discount_rate = .02;
outage = 0;
reliability = 0;
rejuv_pres_val = a * replacement_cost * mean_length * pot_candidates * accept_rate;
ini_rejuv_cost = a * replacement_cost * mean_length * pot_candidates * accept_rate;
failure_rate = [.05,.24,.53,.89,1.32,1.77,2.26,2.76,3.25,3.72,4.15,4.54,4.86,5.11,5.27,5.36,5.35,5.27,5.10,4.86,4.57,4.22,3.85,3.46,3.06,2.66,2.28,1.93,1.61,1.31]./100;
rejuv_ind_yr_val = zeros(1,30);
for i = 1:length(replacement_rate)
    %cost of replacing segements per year
    reject_ind_yr_val(i) = pot_candidates * reject_rate * replacement_rate(i) * mean_length * replacement_cost;
    %present value cost with discount rate over 5 years
    reject_pres_val = reject_pres_val + (reject_ind_yr_val(i)/(1+discount_rate)^i);
end
for j = 1:length(rejuv_ind_yr_val)
    %cost of injecting segments per year
    rejuv_ind_yr_val(j) = pot_candidates .* accept_rate .* failure_rate(j) .* mean_length .* replacement_cost;
    %present value cost with discount rate over 30 years
    rejuv_pres_val = rejuv_pres_val +  (rejuv_ind_yr_val(j)/(1+discount_rate)^j);
end
%total system replacement
total_sys_replace = pot_candidates * mean_length * replacement_cost;
%total rejuvenation cost
total_rejuv_cost = outage + reliability + rejuv_pres_val + reject_pres_val;
end