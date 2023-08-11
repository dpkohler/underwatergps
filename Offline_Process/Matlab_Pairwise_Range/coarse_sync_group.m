function [coarse_results] = coarse_sync_group(rx_signal, train_sig2s, Ns, GI, L, PN_seq, user_id, group_users, save_fig)
    group_size = length(group_users);
    %% using the cross correlation to detect preamble
    [acor, lag] = xcorr(rx_signal, train_sig2s(:, user_id + 1));
    max_number = 30;
    max_peak_corr = max(acor);
    [pks,locs]=findpeaks(acor,'MinPeakHeight',max_peak_corr*0.1,'MinPeakDistance',44100*4);
    seek_back = 730;
    Ns2 = length(train_sig2s(:, user_id + 1 ));

    new_locs = [];
    % look back to find the previous high peak instead of highest peak in consideration of multipath
    for i = 1:length(locs)
        l= locs(i);
        p = pks(i);
        p_threshold = p*0.55;
    
        for j = seek_back : -1 : 0
            l_new = l - j;
            if(acor(l_new) > p_threshold)
                new_locs = [new_locs l_new];
                break;
            end
        end
    end
    
    begin_idx = 2-lag(1);
    acor1 = acor(begin_idx:end);
    locs0 = lag(locs);
    locs = lag(new_locs);
    negative_index = locs0<=0;
    locs0(negative_index) =[];
    locs(negative_index) =[];
    negative_index = locs<=0;
    locs0(negative_index) =[];
    locs(negative_index) =[];
    
    figure
    hold on
    plot(acor1)
    scatter(locs0, acor1(locs0), 'rx')
    scatter(locs, acor1(locs), 'ko')

    %% using naiser corr to exclude sparkle noise
    num_user = group_size - 1;
    fs = 44100;
    interval = 0.36*fs; 
    reply_interval = 0.85 *fs;
%     interval = 0.32*fs; 
%     reply_interval = 0.6 *fs;
    variance_sample = 2000;
    sig_len = Ns2 + variance_sample*2;
        
    coarse_results = [];
    offsets_all = [0, reply_interval];
    for i =3:12
        offsets_all = [offsets_all, reply_interval+(i-2)*interval];
    end
    
    offsets = [];
    user_idx = -1;
    for u = 1:length(group_users)
        id = group_users(u);
        if(id == user_id)
            user_idx = u;
        end
        offsets = [offsets, offsets_all(id+1)];
    end
    
  
    for idx = 2:length(locs)
        if idx > max_number
            break
        end
        self_idx = locs(idx); % self chirp

        begin_indexes = zeros(1, group_size);
        results_indexes = -1*ones(1, group_size);
        for chirp_id = 1:group_size
            begin_indexes(chirp_id) = self_idx - offsets(user_idx) + offsets(chirp_id) - 800;
        end 


        begin_id = begin_indexes(1);
        figure
        plot(rx_signal(begin_id+1:begin_id+48000*2));
        %%%% leader's chirp

        num = 0;
        if(idx < 0)
            if(save_fig)
                f = figure('Name', int2str(100 + idx),'visible','off');
            else
                f = figure('Name', int2str(100 + idx),'visible','on');
            end
            clf(f);
        end

        miss_leader = 0;

        for begin_id = begin_indexes
            num = num + 1;
            if(miss_leader == 0 || num == user_id + 1)
                if begin_id + sig_len < length(rx_signal) && begin_id > 0
                    rx1 = rx_signal(begin_id+1:begin_id+sig_len);
                elseif begin_id <= 0
                    begin_indexes(num) = 1;
                    rx1 = rx_signal(1:begin_id+sig_len);
                else
                    rx1 = rx_signal(begin_id + 1:end);
                end
            else
                rx1 = rx_signal(begin_id+1 - interval*5 :begin_id+sig_len- interval*5);
            end

            [naiser_idx, peak, Mn] = naiser_corr3(rx1, Ns, GI, L, PN_seq);
            if(user_id == 0)
                if(naiser_idx < 0)
                    rx1 =  rx_signal(begin_id+1+interval*5:begin_id+sig_len+interval*5);
                    [naiser_idx, peak, Mn] = naiser_corr3(rx1, Ns, GI, L, PN_seq);
                    now_offset =  begin_indexes(num) + interval*5;
                else
                    now_offset =  begin_indexes(num);
                end
            else
                if(num == 1 && naiser_idx < 0)
                    rx1 =  rx_signal(begin_id+1-interval*5:begin_id+sig_len-interval*5);
                    [naiser_idx, peak, Mn] = naiser_corr3(rx1, Ns, GI, L, PN_seq);
                    now_offset =  begin_indexes(num) - interval*5;
                    miss_leader = 1;
                elseif(miss_leader == 1 && num ~= user_id + 1)
                    now_offset =  begin_indexes(num) - interval*5;
                else
                    now_offset =  begin_indexes(num);
                end
            end

            [acor_i, lag_i] = xcorr(rx1, train_sig2s(:, num));

            begin_id = floor(length(acor_i)/2);
            acor_i_seg = acor_i( begin_id + 1: end);
            if(naiser_idx > 0)
                
                [max_val, max_id] = max(acor_i_seg);
                p_threshold =max_val*0.6; %0.65
    
                for j = seek_back : -1 : 0
                    l_new = max_id - j;
                    if (l_new <= 0)
                        continue;
                    end
                    if(acor_i_seg(l_new) > p_threshold)
                        results_indexes(num) = lag_i(l_new) + begin_id + now_offset;
                        break; 
                    end
                end

            end
            
%             results_indexes(num) - begin_indexes(num)
            if(idx < 4 )
                subplot(group_size, 3, 3*num - 2)
                plot(rx1)
                subplot(group_size, 3, 3*num - 1)
                plot(acor_i_seg)
                xline(results_indexes(num) - begin_indexes(num) )
                subplot(group_size, 3, 3*num)
                plot(Mn)
                ylim([-0.3,1])
                xlim([0, 600])
                
            end


        end
%         if(save_fig)
%             saveas(f,strcat('results/coarse_', int2str(user_id) , '_', int2str(idx-1), '.jpg'));
%         end
        coarse_results = [coarse_results; results_indexes];
       
    end
   

end