clear 
clc
fs = 1e6; 									% Sampling frecuency
f  = 10e3; 									% Message frecuency

B = 6; 	  									% Number of bits
N = 100;  									% Length of signal
t = (0:(N-1))*(1/fs); 

sig_an  = 0.5 * sin(2*pi*f*t)+0.5;
d_step  = max(sig_an)/(2^6-1);
sig_q   = round(sig_an/d_step);

%sig_out = dec2bin(sig_q);

out=[];

for(i=1:1:N)
		aux(1:sig_q(i))=ones();
    aux(1+sig_q(i):(2^B-1))=zeros();
    out=[out,aux]; 
end

