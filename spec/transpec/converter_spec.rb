# coding: utf-8

require 'spec_helper'
require 'transpec/converter'

module Transpec
  describe Converter do
    subject(:converter) { Converter.new(configuration) }
    let(:configuration) { Configuration.new }

    describe '#convert_file!' do
      include_context 'isolated environment'

      let(:file_path) { 'sample_spec.rb' }

      before do
        File.write(file_path, 'This is a spec')
        File.utime(0, 0, file_path)
        converter.stub(:rewrite).and_return('This is the converted spec')
      end

      it 'overwrites the passed file path' do
        converter.convert_file!(file_path)
        File.read(file_path).should == 'This is the converted spec'
      end

      context 'when the source does not need convert' do
        before do
          converter.stub(:rewrite).and_return('This is a spec')
        end

        it 'does not touch the file' do
          converter.convert_file!(file_path)
          File.mtime(file_path).should == Time.at(0)
        end
      end
    end

    describe '#convert' do
      subject { converter.convert(source) }

      let(:source) do
        <<-END
          describe 'example group' do
            it 'is an example' do
              something.should == 'foo'
              something.should_receive(:message)
            end
          end
        END
      end

      it 'dispatches found syntax objects to each handler method' do
        converter.should_receive(:process_should).with(an_instance_of(Syntax::Should))
        converter.should_receive(:process_should_receive).with(an_instance_of(Syntax::ShouldReceive))
        converter.convert(source)
      end

      context 'when the source has overlapped convert targets' do
        let(:source) do
          <<-END
            describe 'example group' do
              it 'is an example' do
                object.stub(:message => mock('something'))
              end
            end
          END
        end

        let(:expected_source) do
          <<-END
            describe 'example group' do
              it 'is an example' do
                allow(object).to receive(:message).and_return(double('something'))
              end
            end
          END
        end

        it 'converts all targets properly' do
          should == expected_source
        end

        it 'adds records for only completed conversions' do
          converter.convert(source)
          converter.report.records.count.should == 2
        end
      end

      context 'when the source has a monkey-patched expectation outside of example group context' do
        before do
          configuration.convert_to_expect_to_matcher = true
          converter.stub(:warn)
        end

        let(:source) do
          <<-END
            describe 'example group' do
              class SomeClass
                def some_method
                  1.should == 1
                end
              end

              it 'is an example' do
                SomeClass.new.some_method
              end
            end
          END
        end

        it 'does not convert the expectation to non-monkey-patch syntax' do
          should == source
        end
      end
    end

    describe '#process_should' do
      let(:should_object) { double('should_object').as_null_object }

      context 'when Configuration#convert_to_expect_to_matcher? is true' do
        before { configuration.convert_to_expect_to_matcher = true }

        context 'and Configuration#negative_form_of_to is "not_to"' do
          before { configuration.negative_form_of_to = 'not_to' }

          it 'invokes Should#expectize! with "not_to"' do
            should_object.should_receive(:expectize!).with('not_to', anything)
            converter.process_should(should_object)
          end
        end

        context 'and Configuration#negative_form_of_to is "to_not"' do
          before { configuration.negative_form_of_to = 'to_not' }

          it 'invokes Should#expectize! with "to_not"' do
            should_object.should_receive(:expectize!).with('to_not', anything)
            converter.process_should(should_object)
          end
        end

        context 'and Configuration#parenthesize_matcher_arg is true' do
          before { configuration.parenthesize_matcher_arg = true }

          it 'invokes Should#expectize! with true as second argument' do
            should_object.should_receive(:expectize!).with(anything, true)
            converter.process_should(should_object)
          end
        end

        context 'and Configuration#parenthesize_matcher_arg is false' do
          before { configuration.parenthesize_matcher_arg = false }

          it 'invokes Should#expectize! with false as second argument' do
            should_object.should_receive(:expectize!).with(anything, false)
            converter.process_should(should_object)
          end
        end
      end

      context 'when Configuration#convert_to_expect_to_matcher? is false' do
        before { configuration.convert_to_expect_to_matcher = false }

        it 'does not invoke Should#expectize!' do
          should_object.should_not_receive(:expectize!)
          converter.process_should(should_object)
        end
      end
    end

    describe '#process_should_receive' do
      let(:should_receive_object) { double('should_receive_object').as_null_object }

      shared_examples 'does nothing' do
        it 'does nothing' do
          should_receive_object.should_not_receive(:expectize!)
          should_receive_object.should_not_receive(:allowize_any_number_of_times!)
          should_receive_object.should_not_receive(:stubize_any_number_of_times!)
          converter.process_should_receive(should_receive_object)
        end
      end

      context 'when ShouldReceive#useless_expectation? returns true' do
        before { should_receive_object.stub(:useless_expectation?).and_return(true) }

        context 'and Configuration#replace_deprecated_method? is true' do
          before { configuration.replace_deprecated_method = true }

          context 'and Configuration#convert_to_allow_to_receive? is true' do
            before { configuration.convert_to_allow_to_receive = true }

            [true, false].each do |convert_to_expect_to_receive|
              context "and Configuration#convert_to_expect_to_receive? is #{convert_to_expect_to_receive}" do
                before { configuration.convert_to_expect_to_receive = convert_to_expect_to_receive }

                context 'and Configuration#negative_form_of_to is "not_to"' do
                  before { configuration.negative_form_of_to = 'not_to' }

                  it 'invokes ShouldReceive#allowize_useless_expectation! with "not_to"' do
                    should_receive_object.should_receive(:allowize_useless_expectation!).with('not_to')
                    converter.process_should_receive(should_receive_object)
                  end
                end

                context 'and Configuration#negative_form_of_to is "to_not"' do
                  before { configuration.negative_form_of_to = 'to_not' }

                  it 'invokes ShouldReceive#allowize_useless_expectation! with "to_not"' do
                    should_receive_object.should_receive(:allowize_useless_expectation!).with('to_not')
                    converter.process_should_receive(should_receive_object)
                  end
                end
              end
            end
          end

          context 'and Configuration#convert_to_allow_to_receive? is false' do
            before { configuration.convert_to_allow_to_receive = false }

            [true, false].each do |convert_to_expect_to_receive|
              context "and Configuration#convert_to_expect_to_receive? is #{convert_to_expect_to_receive}" do
                before { configuration.convert_to_expect_to_receive = convert_to_expect_to_receive }

                it 'invokes ShouldReceive#stubize_useless_expectation!' do
                  should_receive_object.should_receive(:stubize_useless_expectation!)
                  converter.process_should_receive(should_receive_object)
                end
              end
            end
          end
        end

        context 'and Configuration#replace_deprecated_method? is false' do
          before { configuration.replace_deprecated_method = false }

          [true, false].each do |convert_to_allow_to_receive|
            context "and Configuration#convert_to_allow_to_receive? is #{convert_to_allow_to_receive}" do
              before { configuration.convert_to_allow_to_receive = convert_to_allow_to_receive }

              context 'and Configuration#convert_to_expect_to_receive? is true' do
                before { configuration.convert_to_expect_to_receive = true }

                context 'and Configuration#negative_form_of_to is "not_to"' do
                  before { configuration.negative_form_of_to = 'not_to' }

                  it 'invokes ShouldReceive#expectize! with "not_to"' do
                    should_receive_object.should_receive(:expectize!).with('not_to')
                    converter.process_should_receive(should_receive_object)
                  end
                end

                context 'and Configuration#negative_form_of_to is "to_not"' do
                  before { configuration.negative_form_of_to = 'to_not' }

                  it 'invokes ShouldReceive#expectize! with "to_not"' do
                    should_receive_object.should_receive(:expectize!).with('to_not')
                    converter.process_should_receive(should_receive_object)
                  end
                end
              end

              context 'and Configuration#convert_to_expect_to_receive? is false' do
                before { configuration.convert_to_expect_to_receive = false }

                include_examples 'does nothing'
              end
            end
          end
        end
      end

      context 'when ShouldReceive#useless_expectation? returns false' do
        before { should_receive_object.stub(:useless_expectation?).and_return(false) }

        context 'and Configuration#convert_to_expect_to_receive? is true' do
          before { configuration.convert_to_expect_to_receive = true }

          [true, false].each do |replace_deprecated_method|
            context "and Configuration#replace_deprecated_method? is #{replace_deprecated_method}" do
              before { configuration.replace_deprecated_method = replace_deprecated_method }

              [true, false].each do |convert_to_allow_to_receive|
                context "and Configuration#convert_to_allow_to_receive? is #{convert_to_allow_to_receive}" do
                  before { configuration.convert_to_allow_to_receive = convert_to_allow_to_receive }

                  context 'and Configuration#negative_form_of_to is "not_to"' do
                    before { configuration.negative_form_of_to = 'not_to' }

                    it 'invokes ShouldReceive#expectize! with "not_to"' do
                      should_receive_object.should_receive(:expectize!).with('not_to')
                      converter.process_should_receive(should_receive_object)
                    end
                  end

                  context 'and Configuration#negative_form_of_to is "to_not"' do
                    before { configuration.negative_form_of_to = 'to_not' }

                    it 'invokes ShouldReceive#expectize! with "to_not"' do
                      should_receive_object.should_receive(:expectize!).with('to_not')
                      converter.process_should_receive(should_receive_object)
                    end
                  end
                end
              end
            end
          end
        end

        context 'and Configuration#convert_to_expect_to_receive? is false' do
          before { configuration.convert_to_expect_to_receive = false }

          [true, false].each do |replace_deprecated_method|
            context "and Configuration#replace_deprecated_method? is #{replace_deprecated_method}" do
              before { configuration.replace_deprecated_method = replace_deprecated_method }

              [true, false].each do |convert_to_allow_to_receive|
                context "and Configuration#convert_to_allow_to_receive? is #{convert_to_allow_to_receive}" do
                  before { configuration.convert_to_allow_to_receive = convert_to_allow_to_receive }

                  include_examples 'does nothing'
                end
              end
            end
          end
        end
      end
    end

    describe '#process_method_stub' do
      let(:method_stub_object) { double('method_stub_object').as_null_object }

      shared_examples 'invokes MethodStub#allowize!' do
        it 'invokes MethodStub#allowize!' do
          method_stub_object.should_receive(:allowize!)
          converter.process_method_stub(method_stub_object)
        end
      end

      shared_examples 'does not invoke MethodStub#allowize!' do
        it 'does not invoke MethodStub#allowize!' do
          method_stub_object.should_not_receive(:allowize!)
          converter.process_method_stub(method_stub_object)
        end
      end

      shared_examples 'invokes MethodStub#replace_deprecated_method!' do
        it 'invokes MethodStub#replace_deprecated_method!' do
          method_stub_object.should_receive(:replace_deprecated_method!)
          converter.process_method_stub(method_stub_object)
        end
      end

      shared_examples 'does not invoke MethodStub#replace_deprecated_method!' do
        it 'does not invoke MethodStub#replace_deprecated_method!' do
          method_stub_object.should_not_receive(:replace_deprecated_method!)
          converter.process_method_stub(method_stub_object)
        end
      end

      shared_examples 'invokes MethodStub#remove_allowance_for_no_message!' do
        it 'invokes MethodStub#remove_allowance_for_no_message!' do
          method_stub_object.should_receive(:remove_allowance_for_no_message!)
          converter.process_method_stub(method_stub_object)
        end
      end

      shared_examples 'does not invoke MethodStub#remove_allowance_for_no_message!' do
        it 'does not invoke MethodStub#remove_allowance_for_no_message!' do
          method_stub_object.should_not_receive(:remove_allowance_for_no_message!)
          converter.process_method_stub(method_stub_object)
        end
      end

      context 'when Configuration#convert_to_allow_to_receive? is true' do
        before { configuration.convert_to_allow_to_receive = true }

        context 'and Configuration#replace_deprecated_method? is true' do
          before { configuration.replace_deprecated_method = true }

          include_examples 'invokes MethodStub#allowize!'
          include_examples 'does not invoke MethodStub#replace_deprecated_method!'
          include_examples 'invokes MethodStub#remove_allowance_for_no_message!'
        end

        context 'and Configuration#replace_deprecated_method? is false' do
          before { configuration.replace_deprecated_method = false }

          include_examples 'invokes MethodStub#allowize!'
          include_examples 'does not invoke MethodStub#replace_deprecated_method!'
          include_examples 'does not invoke MethodStub#remove_allowance_for_no_message!'
        end
      end

      context 'when Configuration#convert_to_allow_to_receive? is false' do
        before { configuration.convert_to_allow_to_receive = false }

        context 'and Configuration#replace_deprecated_method? is true' do
          before { configuration.replace_deprecated_method = true }

          include_examples 'does not invoke MethodStub#allowize!'
          include_examples 'invokes MethodStub#replace_deprecated_method!'
          include_examples 'invokes MethodStub#remove_allowance_for_no_message!'
        end

        context 'and Configuration#replace_deprecated_method? is false' do
          before { configuration.replace_deprecated_method = false }

          include_examples 'does not invoke MethodStub#allowize!'
          include_examples 'does not invoke MethodStub#replace_deprecated_method!'
          include_examples 'does not invoke MethodStub#remove_allowance_for_no_message!'
        end
      end
    end

    describe '#process_double' do
      let(:double_object) { double('double_object').as_null_object }

      context 'when Configuration#replace_deprecated_method? is true' do
        before { configuration.replace_deprecated_method = true }

        it 'invokes Double#convert_to_double!' do
          double_object.should_receive(:convert_to_double!)
          converter.process_double(double_object)
        end
      end

      context 'when Configuration#replace_deprecated_method? is false' do
        before { configuration.replace_deprecated_method = false }

        it 'does not invoke Double#convert_to_double!' do
          double_object.should_not_receive(:convert_to_double!)
          converter.process_double(double_object)
        end
      end
    end

    describe '#process_be_close' do
      let(:be_close_object) { double('be_close_object').as_null_object }

      context 'when Configuration#replace_deprecated_method? is true' do
        before { configuration.replace_deprecated_method = true }

        it 'invokes BeClose#convert_to_be_within!' do
          be_close_object.should_receive(:convert_to_be_within!)
          converter.process_be_close(be_close_object)
        end
      end

      context 'when Configuration#replace_deprecated_method? is true' do
        before { configuration.replace_deprecated_method = false }

        it 'does not invoke BeClose#convert_to_be_within!' do
          be_close_object.should_not_receive(:convert_to_be_within!)
          converter.process_be_close(be_close_object)
        end
      end
    end

    describe '#process_raise_error' do
      let(:raise_error_object) { double('raise_error_object').as_null_object }

      context 'when Configuration#replace_deprecated_method? is true' do
        before { configuration.replace_deprecated_method = true }

        it 'invokes RaiseError#remove_error_specification_with_negative_expectation!' do
          raise_error_object.should_receive(:remove_error_specification_with_negative_expectation!)
          converter.process_raise_error(raise_error_object)
        end
      end

      context 'when Configuration#replace_deprecated_method? is true' do
        before { configuration.replace_deprecated_method = false }

        it 'does not invoke BeClose#convert_to_be_within!' do
          raise_error_object.should_not_receive(:remove_error_specification_with_negative_expectation!)
          converter.process_raise_error(raise_error_object)
        end
      end
    end

    describe '#process_rspec_configure' do
      let(:rspec_configure) { double('rspec_configure').as_null_object }

      context 'when #need_to_modify_expectation_syntax_configuration? returns true' do
        before do
          converter.stub(:need_to_modify_expectation_syntax_configuration?).and_return(true)
        end

        it 'invokes RSpecConfigure#modify_expectation_syntaxes! with :expect' do
          rspec_configure.should_receive(:modify_expectation_syntaxes!).with(:expect)
          converter.process_rspec_configure(rspec_configure)
        end
      end

      context 'when #need_to_modify_expectation_syntax_configuration? returns false' do
        before do
          converter.stub(:need_to_modify_expectation_syntax_configuration?).and_return(false)
        end

        it 'does not invoke RSpecConfigure#modify_expectation_syntaxes!' do
          rspec_configure.should_not_receive(:modify_expectation_syntaxes!)
          converter.process_rspec_configure(rspec_configure)
        end
      end

      context 'when #need_to_modify_mock_syntax_configuration? returns true' do
        before do
          converter.stub(:need_to_modify_mock_syntax_configuration?).and_return(true)
        end

        it 'invokes RSpecConfigure#modify_mock_syntaxes! with :expect' do
          rspec_configure.should_receive(:modify_mock_syntaxes!).with(:expect)
          converter.process_rspec_configure(rspec_configure)
        end
      end

      context 'when #need_to_modify_mock_syntax_configuration? returns false' do
        before do
          converter.stub(:need_to_modify_mock_syntax_configuration?).and_return(false)
        end

        it 'does not invoke RSpecConfigure#modify_mock_syntaxes!' do
          rspec_configure.should_not_receive(:modify_mock_syntaxes!)
          converter.process_rspec_configure(rspec_configure)
        end
      end
    end

    shared_examples 'syntaxes' do |syntaxes_reader, expectations|
      expectations.each do |current_syntaxes, return_value|
        context "and RSpecConfigure##{syntaxes_reader} returns #{current_syntaxes.inspect}" do
          before do
            rspec_configure.stub(syntaxes_reader).and_return(current_syntaxes)
          end

          it "returns #{return_value}" do
            should == return_value
          end
        end
      end

      context "and RSpecConfigure##{syntaxes_reader} raises UnknownSyntaxError" do
        before do
          rspec_configure.stub(syntaxes_reader).and_raise(Syntax::RSpecConfigure::UnknownSyntaxError)
        end

        it 'returns false' do
          should be_false
        end
      end
    end

    describe '#need_to_modify_expectation_syntax_configuration?' do
      subject { converter.need_to_modify_expectation_syntax_configuration?(rspec_configure) }
      let(:rspec_configure) { double('rspec_configure') }

      context 'when Configuration#convert_to_expect_to_matcher? is true' do
        before { configuration.convert_to_expect_to_matcher = true }

        include_examples 'syntaxes', :expectation_syntaxes, {
          []                 => false,
          [:should]          => true,
          [:expect]          => false,
          [:should, :expect] => false
        }
      end

      context 'when Configuration#convert_to_expect_to_matcher? is false' do
        before { configuration.convert_to_expect_to_matcher = false }

        include_examples 'syntaxes', :expectation_syntaxes, {
          []                 => false,
          [:should]          => false,
          [:expect]          => false,
          [:should, :expect] => false
        }
      end
    end

    describe '#need_to_modify_mock_syntax_configuration?' do
      subject { converter.need_to_modify_mock_syntax_configuration?(rspec_configure) }
      let(:rspec_configure) { double('rspec_configure') }

      context 'when Configuration#convert_to_expect_to_receive? is true' do
        before { configuration.convert_to_expect_to_receive = true }

        context 'and Configuration#convert_to_allow_to_receive? is true' do
          before { configuration.convert_to_allow_to_receive = true }

          include_examples 'syntaxes', :mock_syntaxes, {
            []                 => false,
            [:should]          => true,
            [:expect]          => false,
            [:should, :expect] => false
          }
        end

        context 'and Configuration#convert_to_allow_to_receive? is false' do
          before { configuration.convert_to_allow_to_receive = false }

          include_examples 'syntaxes', :mock_syntaxes, {
            []                 => false,
            [:should]          => true,
            [:expect]          => false,
            [:should, :expect] => false
          }
        end
      end

      context 'when Configuration#convert_to_expect_to_receive? is false' do
        before { configuration.convert_to_expect_to_receive = false }

        context 'and Configuration#convert_to_allow_to_receive? is true' do
          before { configuration.convert_to_allow_to_receive = true }

          include_examples 'syntaxes', :mock_syntaxes, {
            []                 => false,
            [:should]          => true,
            [:expect]          => false,
            [:should, :expect] => false
          }
        end

        context 'and Configuration#convert_to_allow_to_receive? is false' do
          before { configuration.convert_to_allow_to_receive = false }

          include_examples 'syntaxes', :mock_syntaxes, {
            []                 => false,
            [:should]          => false,
            [:expect]          => false,
            [:should, :expect] => false
          }
        end
      end
    end
  end
end