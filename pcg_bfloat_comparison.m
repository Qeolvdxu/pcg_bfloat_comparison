% TEST custom PCG algorithm with IEEE vs BFloat data types
test_count = 20;
sz = [0 6];

table_cell = cell(test_count,6);
name_cell = cell(6,1);
name_cell{1,1}="Test Number";
name_cell{2,1}="Matrix";
name_cell{3,1}="Size";
name_cell{4,1}="Density";
name_cell{5,1}="Default Iteration Count";
name_cell{6,1}="Bfloat16 Iteration Count";

% Sparse Matrix files from Suitesparse Collection
matrices = {'arc130.mtx','494_bus.mtx','662_bus.mtx','685_bus.mtx','1138_bus.mtx'...
            ,'bcsstk01.mtx','bcsstk02.mtx','bcsstk03.mtx','bcsstk04.mtx','bcsstk05.mtx'...
            ,'bcsstk06.mtx','bcsstk07.mtx','bcsstk08.mtx','bcsstk09.mtx','bcsstk10.mtx'...
            ,'bcsstk11.mtx','bcsstk12.mtx','bcsstk13.mtx','bcsstk14.mtx','bcsstk15.mtx'};

% counters
it_total1 = 1;
it_total2 = 1;
nonzero_its = 0;

fprintf("Tests done:")
for cur_test=1:test_count

    % Read matrix files
    cur_matrix = matrices{cur_test};%'arc130.mtx';
    [A, ~, A_size, nonzero_count] = mmread(cur_matrix);
    b = randn(size(A,1), 1);

    % calculate iteration count using standard floats
    [~, ~, ~, itcount1] = custom_pcg(A, b, 1e-7, 10000, eye(A_size), 1);

     % calculate iteration count using brain floats
    A = chop(A,7);
    [~, ~, ~, itcount2] = custom_pcg(A, b, 1e-7, 10000, eye(A_size), 1);

    % add data to table, show progress, get mean
    table_cell{cur_test,1} = cur_test;
    table_cell{cur_test,2} = cur_matrix;
    table_cell{cur_test,3} = A_size;
    table_cell{cur_test,4} = A_size/nonzero_count;
    table_cell{cur_test,5} = itcount1;
    table_cell{cur_test,6} = itcount2;

    fprintf("%3d",cur_test)
    if(itcount1 ~= 0 && itcount2 ~= 0)
        it_total1 = it_total1 * itcount1;
        it_total2 = it_total2 * itcount2;
        nonzero_its = nonzero_its + 1;
    end
end
fprintf("\n")
table = cell2table(table_cell,'VariableNames',name_cell);
prettyprint(table)