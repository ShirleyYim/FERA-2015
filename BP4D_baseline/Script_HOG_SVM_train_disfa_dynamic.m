function Script_HOG_SVM_train_disfa_dynamic()

% Change to your downloaded location
addpath('C:\liblinear\matlab')
addpath('../data extraction/');
%% load shared definitions and AU data
shared_defs;

disfa_au = intersect([1,2,4,5,6,9,12,15,17,20,25,26], all_aus);

% Set up the hyperparameters to be validated
hyperparams.c = 10.^(-7:1:-1);
hyperparams.e = 10.^(-3);
hyperparams.under_ratio = [1];

hyperparams.validate_params = {'c', 'e', 'under_ratio'};

% Set the training function
svm_train = @svm_train_linear;
    
% Set the test function (the first output will be used for validation)
svm_test = @svm_test_linear;

pca_loc = '../pca_generation/generic_face_rigid.mat';

%%
for a=1:numel(aus)
    
    if(ismember(aus(a), disfa_au))
    
        au = aus(a);

        find_BP4D;
        % load the training and testing data for the current fold
        [~, ~, valid_samples, valid_labels, raw_valid, PC, means, scaling] = Prepare_HOG_AU_data_generic_dynamic(train_recs, devel_recs, au, BP4D_dir, hog_data_dir, pca_loc);

        find_DISFA;
        od = cd('../DISFA_baseline/training/');
        all_disfa = [1,2,4,5,6,9,12,15,17,20,25,26];
        rest_aus = setdiff(all_disfa, au);    
        [train_samples_disfa, train_labels_disfa, ~, ~, ~, ~, ~, ~] = Prepare_HOG_AU_data_generic_dynamic(users, au, rest_aus, hog_data_dir);            
        cd(od);
        % Binarise the models            
        train_labels_disfa(train_labels_disfa < 1) = 0;
        train_labels_disfa(train_labels_disfa >= 1) = 1;

        % TODO should valid be included?
        train_samples = train_samples_disfa;
        train_labels = train_labels_disfa;
            
        train_samples = sparse(train_samples);
        valid_samples = sparse(valid_samples);

        %% Cross-validate here                
        [ best_params, ~ ] = validate_grid_search(svm_train, svm_test, false, train_samples, train_labels, valid_samples, valid_labels, hyperparams);

        model = svm_train(train_labels, train_samples, best_params);        

        [prediction, a, actual_vals] = predict(valid_labels, valid_samples, model);

        % Go from raw data to the prediction
        w = model.w(1:end-1)';
        b = model.w(end);

        svs = bsxfun(@times, PC, 1./scaling') * w;

        % Attempt own prediction
        preds_mine = bsxfun(@plus, raw_valid, -means) * svs + b;

        assert(norm(preds_mine - actual_vals) < 1e-8);

        name = sprintf('camera_ready/AU_%d_dynamic_DISFA.dat', au);

        write_lin_dyn_svm(name, means, svs, b, model.Label(1), model.Label(2));

        name = sprintf('camera_ready/AU_%d_dynamic_DISFA.mat', au);

        tp = sum(valid_labels == 1 & prediction == 1);
        fp = sum(valid_labels == 0 & prediction == 1);
        fn = sum(valid_labels == 1 & prediction == 0);
        tn = sum(valid_labels == 0 & prediction == 0);

        precision = tp/(tp+fp);
        recall = tp/(tp+fn);

        f1 = 2 * precision * recall / (precision + recall);    

        save(name, 'model', 'f1', 'precision', 'recall', 'best_params');
    end
end

end

function [model] = svm_train_linear(train_labels, train_samples, hyper)
    comm = sprintf('-s 1 -B 1 -e %.10f -c %.10f -q', hyper.e, hyper.c);
    
    pos_count = sum(train_labels == 1);
    neg_count = sum(train_labels == 0);
    
    if(pos_count * hyper.under_ratio < neg_count)
    
        inds_train = 1:size(train_labels,1);
        neg_samples = inds_train(train_labels == 0);
        reduced_inds = true(size(train_labels,1),1);
        to_rem = round(neg_count -  pos_count * hyper.under_ratio);
        neg_samples = neg_samples(round(linspace(1, size(neg_samples,2), to_rem)));
        
        reduced_inds(neg_samples) = false;

        train_labels = train_labels(reduced_inds, :);
        train_samples = train_samples(reduced_inds, :);
        
    end
        
    model = train(train_labels, train_samples, comm);
end

function [result, prediction] = svm_test_linear(test_labels, test_samples, model)

    w = model.w(1:end-1)';
    b = model.w(end);

    % Attempt own prediction
    prediction = test_samples * w + b;
    l1_inds = prediction > 0;
    l2_inds = prediction <= 0;
    prediction(l1_inds) = model.Label(1);
    prediction(l2_inds) = model.Label(2);
 
    %[prediction, a, actual_vals] = predict(test_labels, test_samples, model);           
    
    tp = sum(test_labels == 1 & prediction == 1);
    fp = sum(test_labels == 0 & prediction == 1);
    fn = sum(test_labels == 1 & prediction == 0);
    tn = sum(test_labels == 0 & prediction == 0);

    precision = tp/(tp+fp);
    recall = tp/(tp+fn);

    f1 = 2 * precision * recall / (precision + recall);

%     result = corr(test_labels, prediction);
    fprintf('F1:%.3f\n', f1);
    if(isnan(f1))
        f1 = 0;
    end
    result = f1;
end
