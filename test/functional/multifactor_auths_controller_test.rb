require 'test_helper'

class MultifactorAuthsControllerTest < ActionController::TestCase
  context 'when logged in' do
    setup do
      @user = create(:user)
      sign_in_as(@user)
      @request.cookies[:mfa_feature] = 'true'
    end

    context 'when mfa enabled' do
      setup do
        @user.enable_mfa!(ROTP::Base32.random_base32, :ui_mfa_only)
      end

      context 'on GET to new mfa' do
        setup do
          get :new
        end

        should respond_with :redirect
        should redirect_to('the profile edit page') { edit_profile_path }
      end

      context 'on POST to create mfa' do
        setup do
          post :create, params: { otp: ROTP::TOTP.new(@user.mfa_seed).now }
        end

        should respond_with :redirect
        should redirect_to('the profile edit page') { edit_profile_path }
        should 'keep mfa enabled' do
          assert @user.reload.mfa_enabled?
        end
      end

      context 'on PUT to update mfa level' do
        context 'on disabling mfa' do
          context 'when otp code is correct' do
            setup do
              put :update, params: { otp: ROTP::TOTP.new(@user.mfa_seed).now, level: 'no_mfa' }
            end

            should respond_with :redirect
            should redirect_to('the profile edit page') { edit_profile_path }
            should 'disable mfa' do
              refute @user.reload.mfa_enabled?
            end
          end

          context 'when otp is recovery code' do
            setup do
              put :update, params: { otp: @user.mfa_recovery_codes.first, level: 'no_mfa' }
            end

            should respond_with :redirect
            should redirect_to('the profile edit page') { edit_profile_path }
            should 'disable mfa' do
              refute @user.reload.mfa_enabled?
            end
          end

          context 'when otp code is incorrect' do
            setup do
              wrong_otp = (ROTP::TOTP.new(@user.mfa_seed).now.to_i.succ % 1_000_000).to_s
              put :update, params: { otp: wrong_otp, level: 'no_mfa' }
            end

            should respond_with :redirect
            should redirect_to('the profile edit page') { edit_profile_path }
            should set_flash.to('Your OTP code is incorrect.')
            should 'keep mfa enabled' do
              assert @user.reload.mfa_enabled?
            end
          end
        end

        context 'on updating to ui_mfa_only' do
          setup do
            @user.ui_and_api_mfa!
            put :update, params: { otp: ROTP::TOTP.new(@user.mfa_seed).now, level: 'ui_mfa_only' }
          end

          should respond_with :redirect
          should redirect_to('the profile edit page') { edit_profile_path }
          should 'update mfa level to ui_mfa_only now' do
            assert @user.reload.ui_mfa_only?
          end
        end

        context 'on updating to ui_and_api_mfa' do
          setup do
            put :update, params: { otp: ROTP::TOTP.new(@user.mfa_seed).now, level: 'ui_and_api_mfa' }
          end

          should respond_with :redirect
          should redirect_to('the profile edit page') { edit_profile_path }
          should 'update make mfa level to ui_and_api_mfa now' do
            assert @user.reload.ui_and_api_mfa?
          end
        end
      end
    end

    context 'when mfa disabled' do
      setup do
        @user.disable_mfa!
      end

      context 'on POST to create mfa' do
        setup do
          @seed = ROTP::Base32.random_base32
          @controller.session[:mfa_seed] = @seed
        end

        context 'when qr-code is not expired' do
          setup do
            @controller.session[:mfa_seed_expire] = Gemcutter::MFA_KEY_EXPIRY.from_now.utc.to_i
            post :create, params: { otp: ROTP::TOTP.new(@seed).now }
          end

          should respond_with :success
          should 'show recovery codes' do
            @user.reload.mfa_recovery_codes.each do |code|
              assert page.has_content?(code)
            end
          end
          should 'enable mfa' do
            assert @user.reload.mfa_enabled?
          end
        end

        context 'when qr-code is expired' do
          setup do
            @controller.session[:mfa_seed_expire] = 1.minute.ago
            post :create, params: { otp: ROTP::TOTP.new(@seed).now }
          end

          should respond_with :redirect
          should redirect_to('the profile edit page') { edit_profile_path }
          should 'set error flash message' do
            refute_empty flash[:error]
          end
          should 'keep mfa disabled' do
            refute @user.reload.mfa_enabled?
          end
        end
      end

      context 'on PUT to update mfa level' do
        setup do
          put :update
        end

        should respond_with :redirect
        should redirect_to('the profile edit page') { edit_profile_path }
        should 'keep mfa disabled' do
          refute @user.reload.mfa_enabled?
        end
      end
    end
  end
end
