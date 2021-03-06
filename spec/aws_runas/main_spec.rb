# Copyright 2015 Chris Marchesi
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'spec_helper'
require 'aws_runas/main'

MFA_ERROR = 'No mfa_serial in selected profile, session will be useless'.freeze
AWS_DEFAULT_CFG_PATH = "#{Dir.home}/.aws/config".freeze
AWS_DEFAULT_CREDENTIALS_PATH = "#{Dir.home}/.aws/credentials".freeze
AWS_LOCAL_CFG_PATH = "#{Dir.pwd}/aws_config".freeze

describe AwsRunAs::Main do
  before(:context) do
    @main = AwsRunAs::Main.new(
      path: MOCK_AWS_CONFIGPATH,
      profile: 'test-profile',
      mfa_code: '123456'
    )
  end

  describe '#sts_client' do
    it 'returns a proper Aws::STS::Client object' do
      expect(@main.sts_client.class.name).to eq('Aws::STS::Client')
    end
  end

  describe '#assume_role' do
    it 'calls out to Aws::AssumeRoleCredentials.new' do
      expect(Aws::AssumeRoleCredentials).to receive(:new).and_call_original
      @main.assume_role
    end

    it 'calls out to Aws::STS::Client.get_session_token when no_role is set' do
      expect_any_instance_of(Aws::STS::Client).to receive(:get_session_token).and_call_original
      ENV.delete('AWS_SESSION_TOKEN')
      @main = AwsRunAs::Main.new(
        path: MOCK_AWS_CONFIGPATH,
        profile: 'test-profile',
        mfa_code: '123456',
        no_role: true
      )
      @main.assume_role
    end

    it 'raises exception when no_role is set and there is no mfa_serial' do
      expect do
        ENV.delete('AWS_SESSION_TOKEN')
        @main = AwsRunAs::Main.new(
          path: MOCK_AWS_NO_MFA_PATH,
          profile: 'test-profile',
          mfa_code: '123456',
          no_role: true
        )
        @main.assume_role
      end.to raise_error(MFA_ERROR)
    end

    it 'calls out to Aws::AssumeRoleCredentials.new with no MFA when AWS_SESSION_TOKEN is set' do
      expect(Aws::AssumeRoleCredentials).to receive(:new).with(hash_including(serial_number: nil)).and_call_original
      ENV.store('AWS_SESSION_TOKEN', 'foo')
      @main.assume_role
    end

    context 'with $HOME/.aws/config (test AWS_SDK_CONFIG_OPT_OUT)' do
      before(:example) do
        Aws.config.update(stub_responses: false)
        allow(File).to receive(:exist?).with(AWS_LOCAL_CFG_PATH).and_return false
        allow(File).to receive(:exist?).with(AWS_DEFAULT_CFG_PATH).and_return true
        allow(File).to receive(:exist?).with(AWS_DEFAULT_CREDENTIALS_PATH).and_return false
        allow(File).to receive(:read).with(AWS_DEFAULT_CFG_PATH).and_return File.read(MOCK_AWS_NO_SOURCE_PATH)
        allow(IniFile).to receive(:load).with(AWS_DEFAULT_CFG_PATH).and_return IniFile.load(MOCK_AWS_NO_SOURCE_PATH)
        allow(Aws::AssumeRoleCredentials).to receive(:new).and_return(
          Aws::AssumeRoleCredentials.new(
            role_arn: 'roleARN',
            role_session_name: 'roleSessionName',
            stub_responses: true
          )
        )
        @main = AwsRunAs::Main.new(
          profile: 'test-profile'
        )
      end

      it 'assumes a role correctly' do
        @main.assume_role
      end
    end
  end

  describe '#credentials_env' do
    before(:context) do
      @env = @main.credentials_env
    end

    context 'with a static, user-defined config path' do
      it 'returns AWS_ACCESS_KEY_ID set in env' do
        expect(@env['AWS_ACCESS_KEY_ID']).to eq('accessKeyIdType')
      end

      it 'returns AWS_SECRET_ACCESS_KEY set in env' do
        expect(@env['AWS_SECRET_ACCESS_KEY']).to eq('accessKeySecretType')
      end

      it 'returns AWS_SESSION_TOKEN set in env' do
        expect(@env['AWS_SESSION_TOKEN']).to eq('tokenType')
      end
    end
  end

  describe '#handoff' do
    before(:context) do
      @env = @main.credentials_env
      ENV.store('SHELL', '/bin/sh')
    end

    it 'calls exec with the environment properly set' do
      expect(@main).to receive(:exec).with(@env, any_args)
      @main.handoff
    end

    it 'starts a shell if no command is specified' do
      expect(@main).to receive(:exec).with(@env, '/bin/sh', *nil)
      @main.handoff
    end

    it 'execs a command when a command is specified' do
      expect(@main).to receive(:exec).with(anything, '/usr/bin/foo', *['--bar', 'baz'])
      @main.handoff(command: '/usr/bin/foo', argv: ['--bar', 'baz'])
    end
  end
end
