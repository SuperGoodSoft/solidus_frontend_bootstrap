require "spec_helper"
require "spree/testing_support/order_walkthrough"

describe "checkout with unshippable items", type: :feature, inaccessible: true do
  let!(:stock_location) { create(:stock_location) }
  let(:order) { Spree::TestingSupport::OrderWalkthrough.up_to(:address) }

  before do
    create(:line_item, order: order)
    order.reload
    line_item = order.line_items.last
    stock_item = stock_location.stock_item(line_item.variant)
    stock_item.adjust_count_on_hand(0)
    stock_item.backorderable = false
    stock_item.save!

    user = create(:user)
    order.user = user
    order.recalculate

    allow_any_instance_of(Spree::CheckoutController).to receive_messages(current_order: order)
    allow_any_instance_of(Spree::CheckoutController).to receive_messages(spree_current_user: user)
    allow_any_instance_of(Spree::CheckoutController).to receive_messages(skip_state_validation?: true)
    allow_any_instance_of(Spree::CheckoutController).to receive_messages(ensure_sufficient_stock_lines: true)
  end

  it "displays and removes" do
    visit spree.checkout_state_path(:delivery)
    expect(page).to have_content("Unshippable Items")

    click_button "Save and Continue"

    order.reload
    expect(order.line_items.count).to eq 1
  end
end
