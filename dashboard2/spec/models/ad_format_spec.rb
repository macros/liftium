require File.dirname(__FILE__) + '/../spec_helper'

describe AdFormat do
  it "should be valid" do
    AdFormat.new.should be_valid
  end
end