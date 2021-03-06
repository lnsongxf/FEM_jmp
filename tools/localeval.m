function val = localeval(xxi,eeta,nodesval)
% Evaluate values inside the rectangular element. 0 <= xxi,eeta <= 1 is the
% local coordinate. nodesval contains the values at the four vertex in
% counter-clockwise order:
% 4------3
% |      |
% |      |
% 1------2
% xxi is on the x-axis and eeta y-axis
if xxi < 0
    error('xxxi < 0');
end
if eeta < 0
    error('eeta < 0');
end
if xxi > 1
    error('xxi > 1');
end
if eeta > 1
    error('eeta > 1');
end
val1 = nodesval(1);
val2 = nodesval(2); 
val3 = nodesval(3); 
val4 = nodesval(4); 
val = (1-xxi)*(1-eeta)*val1 + xxi*(1-eeta)*val2 + xxi*eeta*val3 + (1-xxi)*eeta*val4;
end