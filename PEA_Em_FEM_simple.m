%% Housekeeping
clear
close all
clc
format long
addpath(genpath('./tools'))
addpath(genpath('./param'))
addpath(genpath('~/Dropbox/matlabtools'));


%% Set the stage
mypara_simple;
nA = 17;
nK = 75;
nE = 75;
T = 1e3;
[P,lnAgrid] = rouwen(rrho_z,0,ssigma_z/sqrt(1-rrho_z^2),nA);
Anodes = exp(lnAgrid);
P = P';
P_cdf = cumsum(P,2);
min_lnA = lnAgrid(1); max_lnA = lnAgrid(end);
min_K = 1; max_K = 50;
min_E = 1; max_E = 50;
damp_factor = 0.1;
maxiter = 10000;
tol = 1e-3;
options = optimoptions(@fsolve,'Display','none','Jacobian','off');
irf_periods = 40;


%% Grid creaton
ln_kgrid = linspace(log(min_K),log(max_K),nK);
Knodes = exp(ln_kgrid);
ln_egrid = linspace(log(min_E),log(max_E),nE);
Enodes = exp(ln_egrid);
N = nA*nK*nE;
[Kmesh,Amesh,Nmesh] = meshgrid(Knodes,Anodes,Enodes);
grids.P_cdf = P_cdf;
grids.Anodes = Anodes;

% %% Encapsulate all parameters
% param = [...
%  bbeta; % 1
%  ggamma; % 2
%  kkappa; % 3
%  eeta; % 4
%  rrho; %5
%  ssigma; %6
%  x; % 7
%  aalpha; % 8
%  ddelta; % 9
%  xxi; % 10
%  ttau; % 11
%  z % 12
%  ];

%% Precomputation and initial guess
tot_stuff = zeros(N,1); ustuff = zeros(N,1);
EMKval = zeros(nA,nK,nE); EMEval = EMKval;
EMKval_temp = EMKval; EMEval_temp = EMEval;
% parfor i = 1:N
% 	[i_a,i_k,i_n] = ind2sub([nA,nK,nE],i);
% 	a = Anodes(i_a); k  = Knodes(i_k); n = Nnodes(i_n); %#ok<PFBNS>
% 	tot_stuff(i) = a*k^aalpha*n^(1-aalpha) + (1-ddelta)*k + z*(1-n);
% 	ustuff(i) = xxi*(1-n)^(1-eeta);
% end
if (exist('FEM_PEA_simple.mat','file'))
	load('FEM_PEA_simple.mat','EMKval','EMEval');
else
	EMKval = zeros(nA,nK,nE); EMEval = EMKval;
	EMKval_temp = EMKval; EMEval_temp = EMEval;
	coeff_lnmk = zeros(4,1); coeff_lnme = zeros(4,1);
	coeff_lnmk(1) = 1.088797773684208;
	coeff_lnmk(2) = -0.129812218799966;
	coeff_lnmk(3) = -0.406510500200686;
	coeff_lnmk(4) = -0.115089098685107;

	coeff_lnme(1) = 0.787865722488784;
	coeff_lnme(2) = -0.186393266814723;
	coeff_lnme(3) = -0.366080221457789;
	coeff_lnme(4) = -0.109767893578230;
	parfor i = 1:N
		[i_a,i_k,i_e] = ind2sub([nA,nK,nE],i);
		a = Anodes(i_a); k  = Knodes(i_k); e = Enodes(i_e); %#ok<*PFBNS>
		EMKval(i) = exp([1 log(a) log(k) log(e)]*coeff_lnmk);
		EMEval(i) = exp([1 log(a) log(k) log(e)]*coeff_lnme);
	end
end




%% Iteration
diff = 10; iter = 0;
while (diff>damp_factor*tol && iter <= maxiter)
	% Pack grids, very important
	grids.EMKval = EMKval;
	grids.EMEval = EMEval;
	grids.Knodes = Knodes;
	grids.Enodes = Enodes;

    %% Time iter step, uses endo grid technique
    parfor i = 1:N

        [i_a,i_k,i_e] = ind2sub([nA,nK,nE],i);
        e = Enodes(i_e); k = Knodes(i_k); A = Anodes(i_a);
		state = [A k e];

		% Find current control vars
		control = state2control_FEM_simple(state,i_a,grids,param);
		kplus = control.kplus;
		eplus = control.eplus;

		% Find the expected EM
        EMK_hat = 0; EME_hat = 0;
        for i_node = 1:nA
            aplus = Anodes(i_node);
			stateplus = [aplus kplus eplus];
			control_plus = state2control_FEM_simple(stateplus,i_node,grids,param);

			EMK_hat = EMK_hat + P(i_a,i_node)*control_plus.mk;
			EME_hat = EME_hat + P(i_a,i_node)*control_plus.me;
        end

        EMKval_temp(i) = EMK_hat;
        EMEval_temp(i) = EME_hat;
    end

    %% Damped update
    EMKval_new = (damp_factor)*EMKval_temp+(1-damp_factor)*EMKval;
    EMEval_new = (damp_factor)*EMEval_temp+(1-damp_factor)*EMEval;

    %% Compute norm
    diff = norm([EMKval(:);EMEval(:)]-[EMKval_new(:);EMEval_new(:)],Inf);

    %% Update
    EMKval = EMKval_new;
    EMEval = EMEval_new;
    iter = iter+1;
    %% Display something
    disp(iter);
    disp(diff);

	save('FEM_PEA_simple.mat');

end;

%% Inspect policy function
i_k = ceil(nK-5);
i_E = ceil(5);
kplus_high = zeros(1,length(Anodes));
q_high = kplus_high;
CIPI_high = q_high;
f_high = q_high;
v_high = q_high;
for i_A = 1:length(Anodes)
	state(1) = Anodes(i_A); state(3) = Enodes(i_E);
	state(2) = Knodes(i_k); e = state(3);
	control = state2control_FEM_simple(state,i_A,grids,param);
	kplus_high(i_A) = control.kplus;
	q_high(i_A) = control.q;
	eplus = control.eplus;
	CIPI_high(i_A) = eplus - e;
	f_high(i_A) = control.f;
	v_high(i_A) = control.v;
end

i_k = ceil(5);
i_E = ceil(nE-5);
kplus_low = zeros(1,length(Anodes));
q_low = kplus_low;
CIPI_low = q_low;
v_low = q_low;
f_low = q_low;
for i_A = 1:length(Anodes)
	state(1) = Anodes(i_A); state(3) = Enodes(i_E);
	state(2) = Knodes(i_k); e = state(3);
	control = state2control_FEM_simple(state,i_A,grids,param);
	kplus_low(i_A) = control.kplus;
	q_low(i_A) = control.q;
	eplus = control.eplus;
	CIPI_low(i_A) = eplus - e;
	v_low(i_A) = control.v;
	f_low(i_A) = control.f;
end

figure
plot(Anodes,CIPI_low,'-b',Anodes,CIPI_high,'-.r')
title('CIPI')
legend('low','high')
xlabel('TFP')

figure
plot(Anodes,v_low,'-b',Anodes,v_high,'-.r')
title('Demand')
legend('low','high')
xlabel('TFP')

figure
plot(Anodes,f_low,'-b',Anodes,f_high,'-.r')
title('Sell Prob.')
legend('low','high')
xlabel('TFP')

figure
plot(Anodes,q_low,'-b',Anodes,q_high,'-.r')
title('Buy Prob.')
legend('low','high')
xlabel('TFP')


%% Simulation
P_cdf = cumsum(P,2);
aindexsim = zeros(1,T); aindexsim(1) = ceil(nA/2);
ksim = kbar*ones(1,T); esim = ebar*ones(1,T);
asim = ones(1,T); ysim = ones(1,T); qsim = zeros(1,T);
% tthetasim = zeros(1,T); vsim = zeros(1,T); usim = zeros(1,T);
for t = 1:T
    asim(t) = Anodes(aindexsim(t)); a = asim(t);
    k = ksim(t); e = esim(t);
	state = [a k e];
	y = a*k^aalpha;
	ysim(t) = y;

	control = state2control_FEM_simple(state,aindexsim(t),grids,param);
    qsim(t) = control.q;

    if t <= T-1
        uu = rand;
        aindexsim(t+1) = find(P_cdf(aindexsim(t),:)>=uu,1,'first');
        ksim(t+1) = control.kplus;
        esim(t+1) = control.eplus;
    end
end

%% Dating and Check asymmetry
CIPI_sim = esim(2:end)-esim(1:end-1);
[recess] = bryBos(ysim',1);
figure
plot(ysim);
hold on
recess_shade(recess,'yellow')

% steepness
xF = CIPI_sim';
output = wilcoxon(xF,recess(2:end));
totalOutput = [[repmat([6 4],2,1) [1:2]' output]];
disp('            avg. contr.    avg. expan.       W-stat     p-value      Wilc t-stat   Basic t-stat  p-value');
rowNames = strvcat('Duration ','Steepness ');
disp(horzcat(rowNames,num2str(output)));

%% Select from Simulation initial states
peak_select = ysim > prctile(ysim,95);
trough_select = ysim < prctile(ysim,5);
peak_inits(1,:) = asim(peak_select);
peak_inits(2,:) = ksim(peak_select);
peak_inits(3,:) = esim(peak_select);
peak_aidx = aindexsim(peak_select);
trough_inits(1,:) = asim(trough_select);
trough_inits(2,:) = ksim(trough_select);
trough_inits(3,:) = esim(trough_select);
trough_aidx = aindexsim(trough_select);

%% Generalized IRF, -2 ssigma shock
periods = 40;
impulse = -2;

parfor i = 1:length(peak_aidx)
	impulse_panel(i,:,:) = ...
	simforward_A(peak_inits(:,i),peak_aidx(i),impulse,periods,grids,param);
	control_panel(i,:,:) = ...
	simforward_A(peak_inits(:,i),peak_aidx(i),0,periods,grids,param);
	GIRF_panel(i,:,:) = impulse_panel(i,:,:)-control_panel(i,:,:);
end
impulse_peak_badshock = squeeze(mean(impulse_panel));
control_peak_badshock = squeeze(mean(control_panel));
GIRF_peak_badshock = squeeze(mean(GIRF_panel));

parfor i = 1:length(trough_aidx)
	impulse_panel(i,:,:) = simforward_A(trough_inits(:,i),trough_aidx(i),impulse,periods,grids,param);
	control_panel(i,:,:) = simforward_A(trough_inits(:,i),trough_aidx(i),0,periods,grids,param);
	GIRF_panel(i,:,:) = impulse_panel(i,:,:)-control_panel(i,:,:);
end
impulse_trough_badshock = squeeze(mean(impulse_panel));
control_trough_badshock = squeeze(mean(control_panel));
GIRF_trough_badshock = squeeze(mean(GIRF_panel));

%% Generalized IRF, +2 ssigma shock
impulse = 2;

parfor i = 1:length(peak_aidx)
	impulse_panel(i,:,:) = simforward_A(peak_inits(:,i),peak_aidx(i),impulse,periods,grids,param);
	control_panel(i,:,:) = simforward_A(peak_inits(:,i),peak_aidx(i),0,periods,grids,param);
	GIRF_panel(i,:,:) = impulse_panel(i,:,:)-control_panel(i,:,:);
end
impulse_peak_goodshock = squeeze(mean(impulse_panel));
control_peak_goodshock = squeeze(mean(control_panel));
GIRF_peak_goodshock = squeeze(mean(GIRF_panel));

parfor i = 1:length(trough_aidx)
	impulse_panel(i,:,:) = simforward_A(trough_inits(:,i),trough_aidx(i),impulse,periods,grids,param);
	control_panel(i,:,:) = simforward_A(trough_inits(:,i),trough_aidx(i),0,periods,grids,param);
	GIRF_panel(i,:,:) = impulse_panel(i,:,:)-control_panel(i,:,:);
end
impulse_trough_goodshock = squeeze(mean(impulse_panel));
control_trough_goodshock = squeeze(mean(control_panel));
GIRF_trough_goodshock = squeeze(mean(GIRF_panel));

%% Plotting conditional on state
plotperiods = 20;
% CIPI
figure
plot(1:plotperiods+1,GIRF_peak_badshock(1,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_peak_goodshock(1,1:plotperiods+1),'r-.','LineWidth',3)
xlabel('Periods From Impact')
ylabel('Generalized IRF, Level')
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('CIPI Response, At Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_CIPI_peak_levels','-depsc2')

figure
plot(1:plotperiods+1,...
	 abs(GIRF_peak_badshock(1,1:plotperiods+1))./...
	 abs(GIRF_peak_goodshock(1,1:plotperiods+1)),...
	 'LineWidth',3)
hold on
legend('Ratio at Peak')
xlabel('Periods From Impact')
ylabel('Ratio, -2 Shock/+2 Shock')
title('CIPI Response, Ratio Peak vs Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_CIPI_peak_ratio','-depsc2')

figure
plot(1:plotperiods+1,GIRF_trough_badshock(1,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_trough_goodshock(1,1:plotperiods+1),'r-.','LineWidth',3)
xlabel('Periods From Impact')
ylabel('Generalized IRF, Level')
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('CIPI Response, At trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_CIPI_trough_levels','-depsc2')

figure
plot(1:plotperiods+1,...
	 abs(GIRF_trough_badshock(1,1:plotperiods+1))./...
	 abs(GIRF_trough_goodshock(1,1:plotperiods+1)),...
	 'LineWidth',3)
hold on
legend('Ratio at Trough')
xlabel('Periods From Impact')
ylabel('Ratio, -2 Shock/+2 Shock')
title('CIPI Response, Bad vs Good')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_CIPI_trough_ratio','-depsc2')

% GDP
figure
plot(1:plotperiods+1,GIRF_peak_badshock(2,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_peak_goodshock(2,1:plotperiods+1),'r-.','LineWidth',3)
xlabel('Periods From Impact')
ylabel('Generalized IRF, Level')
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('GDP Response, At Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_GDP_peak_levels','-depsc2')

figure
plot(1:plotperiods+1,GIRF_trough_badshock(2,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_trough_goodshock(2,1:plotperiods+1),'r-.','LineWidth',3)
xlabel('Periods From Impact')
ylabel('Generalized IRF, Level')
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('GDP Response, At Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_GDP_trough_levels','-depsc2')

figure
plot(1:plotperiods+1,...
	 abs(GIRF_peak_badshock(2,1:plotperiods+1))./...
	 abs(GIRF_peak_goodshock(2,1:plotperiods+1)),...
	 'LineWidth',3)
hold on
legend('Ratio at Peak')
xlabel('Periods From Impact')
ylabel('Ratio, -2 Shock/+2 Shock')
title('GDP Response, Ratio Bad Shock vs Good')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_GDP_peak_ratio','-depsc2')

figure
plot(1:plotperiods+1,...
	 abs(GIRF_trough_badshock(2,1:plotperiods+1))./...
	 abs(GIRF_trough_goodshock(2,1:plotperiods+1)),...
	 'LineWidth',3)
hold on
legend('Ratio at Trough')
xlabel('Periods From Impact')
ylabel('Ratio, -2 Shock/+2 Shock')
title('GDP Response, Ratio Bad Shock vs Good Shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_GDP_trough_ratio','-depsc2')

figure
plot(1:plotperiods+1,GIRF_peak_badshock(2,1:plotperiods+1)-GIRF_peak_badshock(2,1:1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_peak_badshock(1,1:plotperiods+1)-GIRF_peak_badshock(1,1:1),'r-.','LineWidth',3)
legend('GDP','CIPI')
title('Relative Level Change to Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/relative2peak_GDP_CIPI_badshock','-depsc2')

figure
plot(1:plotperiods+1,GIRF_peak_badshock(3,1:plotperiods+1)./GIRF_trough_badshock(3,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_peak_goodshock(3,1:plotperiods+1)./GIRF_trough_goodshock(3,1:plotperiods+1),'r-.','LineWidth',3)
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('CIPI/GDP Response, Ratio Peak vs Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_share_twoshocks','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_badshock(3,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(3,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('CIPI/GDP, 2 std negative TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_share_minustwoshock','-depsc2')

% buying prob., q, peak
figure
plot(1:plotperiods+1,GIRF_peak_badshock(4,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_peak_goodshock(4,1:plotperiods+1),'r-.','LineWidth',3)
xlabel('Periods From Impact')
ylabel('Generalized IRF, Level')
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('Buy Prob. Response, At Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_q_peak_levels','-depsc2')

figure
plot(1:plotperiods+1,...
	 abs(GIRF_peak_badshock(4,1:plotperiods+1))./...
	 abs(GIRF_peak_goodshock(4,1:plotperiods+1)),...
	 'LineWidth',3)
hold on
legend('Ratio at Peak')
xlabel('Periods From Impact')
ylabel('Ratio, -2 Shock/+2 Shock')
title('Buy Prob. Response, Ratio Bad vs Good')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_q_peak_ratio','-depsc2')

% buying prob., q, trough
figure
plot(1:plotperiods+1,GIRF_trough_badshock(4,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_trough_goodshock(4,1:plotperiods+1),'r-.','LineWidth',3)
xlabel('Periods From Impact')
ylabel('Generalized IRF, Level')
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('Buy Prob. Response, At Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_q_trough_levels','-depsc2')

figure
plot(1:plotperiods+1,...
	 abs(GIRF_trough_badshock(4,1:plotperiods+1))./...
	 abs(GIRF_trough_goodshock(4,1:plotperiods+1)),...
	 'LineWidth',3)
hold on
legend('Ratio at Trough')
xlabel('Periods From Impact')
ylabel('Ratio, -2 Shock/+2 Shock')
title('Buy Prob. Response, Ratio Bad vs Good')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_q_trough_ratio','-depsc2')

% selling prob., f
figure
plot(1:plotperiods+1,GIRF_peak_badshock(5,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_peak_goodshock(5,1:plotperiods+1),'r-.','LineWidth',3)
xlabel('Periods From Impact')
ylabel('Generalized IRF, Level')
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('Sell Prob. Response, At Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_f_peak_levels','-depsc2')

figure
plot(1:plotperiods+1,...
	 abs(GIRF_peak_badshock(5,1:plotperiods+1))./...
	 abs(GIRF_peak_goodshock(5,1:plotperiods+1)),...
	 'LineWidth',3)
hold on
legend('Ratio at Peak')
xlabel('Periods From Impact')
ylabel('Ratio, -2 Shock/+2 Shock')
title('Sell Prob. Response, Ratio Peak vs Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_f_peak_ratio','-depsc2')

% Demand, V
figure
plot(1:plotperiods+1,GIRF_peak_badshock(6,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_peak_goodshock(6,1:plotperiods+1),'r-.','LineWidth',3)
xlabel('Periods From Impact')
ylabel('Generalized IRF, Level')
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('Demand Response, At Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_V_peak_levels','-depsc2')

%% old stuff, stop above
figure
plot(1:plotperiods+1,...
	 abs(GIRF_peak_badshock(6,1:plotperiods+1))./...
	 abs(GIRF_peak_goodshock(6,1:plotperiods+1)),...
	 'LineWidth',3)
hold on
legend('Ratio at Peak')
xlabel('Periods From Impact')
ylabel('Ratio, -2 Shock/+2 Shock')
title('Demand Response, Ratio Peak vs Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_V_peak_ratio','-depsc2')

% old q
plotperiods = 15;
figure
plot(1:plotperiods+1,GIRF_peak_badshock(4,1:plotperiods+1)./GIRF_trough_badshock(4,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_peak_goodshock(4,1:plotperiods+1)./GIRF_trough_goodshock(4,1:plotperiods+1),'r-.','LineWidth',3)
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('Buy Prob. Response, Ratio Peak vs Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_q_twoshocks','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_badshock(4,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(4,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('Buy Prob., 2 std negative TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('statedependency_q_minustwoshock','-depsc2')

figure
plot(1:plotperiods+1,GIRF_peak_badshock(5,1:plotperiods+1)./GIRF_trough_badshock(5,1:plotperiods+1),'LineWidth',3)
hold on
plot(1:plotperiods+1,GIRF_peak_goodshock(5,1:plotperiods+1)./GIRF_trough_goodshock(5,1:plotperiods+1),'r-.','LineWidth',3)
legend('-2 Std TFP Shock','+2 Std TFP Good Shock')
title('Sell Prob. Response, Ratio Peak vs Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('./figures/statedependency_f_twoshocks','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_badshock(5,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(5,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('Sell Prob., 2 std negative TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('statedependency_f_minustwoshock','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_badshock(6,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(6,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('Demand, 2 std negative TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('statedependency_v_minustwoshock','-depsc2')



figure
plot(1:irf_periods+1,GIRF_peak_goodshock(1,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_goodshock(1,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('CIPI, 2 std positive TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('statedependency_CIPI_plustwoshock','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(2,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_goodshock(2,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('GDP, 2 std positive TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('statedependency_GDP_plustwoshock','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(3,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_goodshock(3,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('CIPI/GDP, 2 std positive TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('statedependency_share_plustwoshock','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(4,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_goodshock(4,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('Buy Prob., 2 std positive TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('statedependency_q_plustwoshock','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(5,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_goodshock(5,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('Sell Prob., 2 std positive TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('statedependency_f_plustwoshock','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(6,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_goodshock(6,:),'r-.','LineWidth',3)
legend('Peak','Trough')
title('Demand, 2 std positive TFP shock')
set(gca,'FontSize',14,'fontWeight','bold')
print('statedependency_v_plustwoshock','-depsc2')
%% Generalized IRF, +2/-2 ssigma shock at peak
figure
plot(1:irf_periods+1,GIRF_peak_goodshock(1,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_peak_badshock(1,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('CIPI, At the Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_CIPI_peak','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(2,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_peak_badshock(2,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('GDP, At the Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_GDP_peak','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(3,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_peak_badshock(3,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('CIPI/GDP, At the Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_share_peak','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(4,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_peak_badshock(4,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('Buy Prob., At the Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_q_peak','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(5,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_peak_badshock(5,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('Sell Prob., At the Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_f_peak','-depsc2')

figure
plot(1:irf_periods+1,GIRF_peak_goodshock(6,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_peak_badshock(6,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('Demand, At the Peak')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_v_peak','-depsc2')

%% Generalized IRF, +2/-2 ssigma shock at trough
figure
plot(1:irf_periods+1,GIRF_trough_goodshock(1,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(1,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('CIPI, At the trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_CIPI_trough','-depsc2')

figure
plot(1:irf_periods+1,GIRF_trough_goodshock(2,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(2,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('GDP, At the trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_GDP_trough','-depsc2')

figure
plot(1:irf_periods+1,GIRF_trough_goodshock(3,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(3,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('CIPI/GDP, At the trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_share_trough','-depsc2')

figure
plot(1:irf_periods+1,GIRF_trough_goodshock(4,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(4,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('Buy Prob., At the Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_q_trough','-depsc2')

figure
plot(1:irf_periods+1,GIRF_trough_goodshock(5,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(5,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('Sell Prob., At the Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_f_trough','-depsc2')

figure
plot(1:irf_periods+1,GIRF_trough_goodshock(6,:),'LineWidth',3)
hold on
plot(1:irf_periods+1,GIRF_trough_badshock(6,:),'r-.','LineWidth',3)
legend('+2 Std Shock','-2 Std Shock')
title('Demand, At the Trough')
set(gca,'FontSize',14,'fontWeight','bold')
print('asymmetry_v_trough','-depsc2')

%% Euler equation error
nk_ee = 60; nnn_ee = 60;
Kgrid = linspace(0.5*k_ss,1.5*k_ss,nk_ee);
Agrid = exp(lnAgrid);
Ngrid = linspace(0.96*n_ss,1.04*n_ss,nnn_ee);
EEerror_c = 999999*ones(nA,nk_ee,nnn_ee);
EEerror_v = 999999*ones(nA,nk_ee,nnn_ee);
cc = zeros(nA,nk_ee,nnn_ee);
vv = zeros(nA,nk_ee,nnn_ee);
tthetattheta = zeros(nA,nk_ee,nnn_ee);
cc_dynare = cc;
vv_dynare = vv;
tthetattheta_dynare = tthetattheta;

for i_a = 1:nA
    a = Agrid(i_a);
    for i_k = 1:nk_ee
        k = Kgrid(i_k);
        for i_e = 1:nnn_ee
            e = Ngrid(i_e);
			tot_stuff = a*k^aalpha*e^(1-aalpha)+(1-ddelta)*k+z*(1-e);
			ustuff = xxi*(1-e)^(1-eeta);

            EMK = globaleval(k,e,Knodes,Enodes,squeeze(EMKval(i_a,:,:)));
            EMF = globaleval(k,e,Knodes,Enodes,squeeze(EMEval(i_a,:,:)));
            c = 1/(bbeta*EMK);
            q = kkappa/c/(bbeta*EMF);

            if q <= 0
                warning('q <= 0!!')
                q = 0;
                ttheta = 0;
                v = 0;
                kplus = tot_stuff - c - kkappa*v;
                nplus = (1-x)*e;
            else
                ttheta = (q/xxi)^(1/(eeta-1));
                v = ttheta*(1-e);
                kplus = tot_stuff - c - kkappa*v;
                nplus = (1-x)*e + xxi*v^eeta*(1-e)^(1-eeta);
            end

            cc(i_a,i_k,i_e) = c;
            cc_dynare(i_a,i_k,i_e) = exp( 2.130385+0.039519*(log(a)/rrho-0)+0.606879*(log(k)-log(k_ss))+0.005573*(log(e)-log(n_ss)) );
            vv(i_a,i_k,i_e) = v;
            vv_dynare(i_a,i_k,i_e) = exp( -2.899249+3.417972*(log(a)/rrho-0)+0.451375*(log(k)-log(k_ss))+(-17.928147)*(log(e)-log(n_ss)) );
            tthetattheta(i_a,i_k,i_e) = ttheta;
            tthetattheta_dynare(i_a,i_k,i_e) = exp( 0+3.417972*(log(a)/rrho-0)+0.451375*(log(k)-log(k_ss))+(-0.767653)*(log(e)-log(n_ss)) );

			% Find expected mh, mf tomorrow if current coeff applies tomorrow
            EMH_hat = 0; EME_hat = 0;
            for i_node = 1:nA
                aplus = Anodes(i_node);
                EMH_plus = globaleval(kplus,nplus,Knodes,Enodes,squeeze(EMKval(i_node,:,:)));
                EMF_plus = globaleval(kplus,nplus,Knodes,Enodes,squeeze(EMEval(i_node,:,:)));
                cplus = 1/(bbeta*EMH_plus);
                qplus = kkappa/cplus/(bbeta*EMF_plus);
				if qplus <= 0
					% warning('qplus <= 0!!')
					qplus = 0;
					tthetaplus = 0;
					vplus = 0;
					EMH_hat = EMH_hat + P(i_a,i_node)*((1-ddelta+aalpha*aplus*(kplus/nplus)^(aalpha-1))/cplus);
					EME_hat = EME_hat + P(i_a,i_node)*(( (1-ttau)*((1-aalpha)*aplus*(kplus/nplus)^aalpha-z-ggamma*cplus) )/cplus );
				else
					tthetaplus = (qplus/xxi)^(1/(eeta-1));
					vplus = tthetaplus*(1-nplus);
					EMH_hat = EMH_hat + P(i_a,i_node)*((1-ddelta+aalpha*aplus*(kplus/nplus)^(aalpha-1))/cplus);
					EME_hat = EME_hat + P(i_a,i_node)*(( (1-ttau)*((1-aalpha)*aplus*(kplus/nplus)^aalpha-z-ggamma*cplus) + (1-x)*kkappa/qplus - ttau*kkappa*tthetaplus )/cplus );
				end
            end

			c_imp = 1/(bbeta*EMH_hat);
			q_imp = kkappa/c_imp/(bbeta*EME_hat);
			ttheta_imp = (q_imp/xxi)^(1/(eeta-1));
			v_imp = ttheta_imp*(1-e);

            EEerror_c(i_a,i_k,i_e) = abs((c-c_imp)/c_imp);
            EEerror_v(i_a,i_k,i_e) = abs((v-v_imp)/v_imp);
        end
    end
end
EEerror_c_inf = norm(EEerror_c(:),inf);
EEerror_v_inf = norm(EEerror_v(:),inf);

EEerror_c_mean = mean(EEerror_c(:));
EEerror_v_mean = mean(EEerror_v(:));

%% Export results
mkdir('results')
h_c = figure;
plot(Kgrid,squeeze(EEerror_c(ceil(nA/2),:,ceil(nnn_ee/2))))
title('Euler Error of Consumption')
print(h_c,'-dpsc','./results/EEerror_c.eps')

h_v = figure;
plot(Kgrid,squeeze(EEerror_v(ceil(nA/2),:,ceil(nnn_ee/2))))
title('Euler Error of Vacancy')
print(h_v,'-dpsc','./results/EEerror_v.eps')

result_mf = @(k,n) globaleval(k,n,Knodes,Enodes,squeeze(EMEval(1,:,:)));
h_EMF = figure;
ezsurf(result_mf,[Kgrid(1),Kgrid(end),Ngrid(1),Ngrid(end)])
print(h_EMF,'-dpsc','./results/EMF.eps')

v_policy = figure;
plot(Ngrid,squeeze(vv(1,1,:)))
title('Vacancy policy at lowerest productivity and capital.')
print(v_policy,'-dpsc','./results/v_policy.eps')

c_policy = figure;
plot(Kgrid,squeeze(cc(ceil(nA/2),:,ceil(nnn_ee/2))),...
Kgrid,squeeze(cc_dynare(ceil(nA/2),:,ceil(nnn_ee/2))))
title('Consumption policies at SS.')
print(c_policy,'-dpsc','./results/c_policy.eps')
xlabel('Capital')

ttheta_policy = figure;
plot(Kgrid,squeeze(tthetattheta(ceil(nA/2),:,ceil(nnn_ee/2))),Kgrid,squeeze(tthetattheta_dynare(ceil(nA/2),:,ceil(nnn_ee/2))))
title('\theta around SS')
print(ttheta_policy,'-dpsc','./results/ttheta_policy.eps')
xlabel('Capital')

ttheta_policyN = figure;
plot(Ngrid,squeeze(tthetattheta(ceil(nA/2),ceil(nk_ee/2),:)),Ngrid,squeeze(tthetattheta_dynare(ceil(nA/2),ceil(nk_ee/2),:)))
title('\theta around SS')
print(ttheta_policyN,'-dpsc','./results/ttheta_policy2.eps')
xlabel('Employment')

ttheta_policyA = figure;
plot(Anodes,squeeze(tthetattheta(:,ceil(nk_ee/2),ceil(nnn_ee/2))),Anodes,squeeze(tthetattheta_dynare(:,ceil(nk_ee/2),ceil(nnn_ee/2))))
title('\theta around SS')
xlabel('Productivity')
print(ttheta_policyA,'-dpsc','./results/ttheta_policy3.eps')

save('PEA_Em_FEM.mat');
