function [data_train, labels_train, data_valid, labels_valid, raw_valid, means_norm, stds_norm] = ...
    Prepare_CLM_AU_data(train_users, au_train, rest_aus, clm_data_dir)

%% This should be a separate function?

input_train_label_files = cell(numel(train_users),1);
    
if(exist('D:/Databases/DISFA', 'file'))
    root = 'D:/Databases/DISFA/';
elseif(exist('F:/datasets/DISFA', 'file'))
    root = 'F:/datasets/DISFA/';
elseif(exist('E:/datasets/DISFA', 'file'))
    root = 'E:/datasets/DISFA/';
elseif(exist('C:/tadas/DISFA/', 'file'))        
    root = 'C:/tadas/DISFA/';    
elseif(exist('../../data_extraction/', 'file'))        
    root = '../../data_extraction/';
else
   fprintf('Can not find the dataset\n'); 
end
    
% This is for loading the labels
for i=1:numel(train_users)   
    input_train_label_files{i} = [root, '/ActionUnit_Labels/', train_users{i}, '/', train_users{i}];
end

% First extracting the labels

% Reading in the geometry data
[train_geom_data, vid_ids_train] = Read_CLM_files_run_med(train_users, clm_data_dir);

% Getting the indices describing the splits (full version)
[training_inds, valid_inds, split] = construct_indices(vid_ids_train, train_users);

% Extracting the labels
labels_train = extract_au_labels(input_train_label_files, au_train);

% Getting the rebalanced training and validation indices and data
[inds_train_rebalanced, inds_valid_rebalanced, ~] = construct_balanced(labels_train, training_inds, valid_inds, rest_aus, input_train_label_files);

% can now extract the needed training labels (do not rebalance validation
% data)
labels_valid = labels_train(valid_inds);
labels_train = labels_train(inds_train_rebalanced);
     
% Grab all data for validation as want good params for all the data
raw_valid = train_geom_data(valid_inds,:);

means_norm = mean(train_geom_data);
stds_norm = std(train_geom_data);

data_valid = bsxfun(@times, bsxfun(@plus, train_geom_data(valid_inds,:), -means_norm), 1./stds_norm);
data_train = bsxfun(@times, bsxfun(@plus, train_geom_data(inds_train_rebalanced,:), -means_norm), 1./stds_norm);

% Do some data clamping of the geometry data?
data_valid(data_valid < -3) = -3;
data_valid(data_valid > 3) = 3;
data_train(data_train < -3) = -3;
data_train(data_train > 3) = 3;

end

function [training_inds, valid_inds, split] = construct_indices(video_inds, train_users)

    % Randomise the training and validation users TODO this makes it worse?
%     train_users = train_users(randperm(numel(train_users)));

    % extract these separately so as to guarantee person independent splits for
    % validation
    split = round(2*numel(train_users)/3);

    users_train = train_users(1:split);

    training_inds = false(size(video_inds));
    for i=1:numel(users_train)
        user_ind = strcmp(video_inds,  users_train(i));
        training_inds = training_inds | user_ind;
    end
    
    users_valid = train_users(split+1:end);
    valid_inds = false(size(video_inds));
    for i=1:numel(users_valid)
        user_ind = strcmp(video_inds,  users_valid(i));
        valid_inds = valid_inds | user_ind;
    end        
end

function [inds_train_rebalanced, inds_valid_rebalanced, sample_length] = construct_balanced(labels_all, training_inds, valid_inds,...
                                                                            rest_aus, input_labels_files)
    
    all_subs = 1:size(labels_all,1);
                                                                        
    labels_train = labels_all(training_inds);
    labels_valid = labels_all(valid_inds);
    
    labels_other_au = zeros(size(labels_all,1), numel(rest_aus));

    % This is used to pick up activity of other AUs for a more 'interesting'
    % data split and not only neutral expressions for negative samples    
    for i=1:numel(rest_aus)
        labels_other_au(:,i) = extract_au_labels(input_labels_files, rest_aus(i));
    end
    
    labels_other_au_train = labels_other_au(training_inds,:);
    labels_other_au_valid = labels_other_au(valid_inds,:);
    
    [ inds_train_rebalanced, sample_length ] = extract_events( labels_train, labels_other_au_train );
    [ inds_valid_rebalanced ] = extract_events( labels_valid, labels_other_au_valid, sample_length );
    
    % Need to move from indices in labels_train space to indices in
    % original labels_all space
    sub_train = all_subs(training_inds);
    inds_train_rebalanced = sub_train(inds_train_rebalanced);
    
    sub_valid = all_subs(valid_inds);
    inds_valid_rebalanced = sub_valid(inds_valid_rebalanced);
end