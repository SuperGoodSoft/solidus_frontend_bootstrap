require "spec_helper"
require "spree/testing_support/order_walkthrough"

describe "Checkout", type: :feature, inaccessible: true do
  let!(:store) { create(:store) }
  let!(:country) { create(:country, states_required: true) }
  let!(:state) { create(:state, country: country) }
  let!(:shipping_method) { create(:shipping_method) }
  let!(:stock_location) { create(:stock_location) }
  let!(:mug) { create(:product, name: "RoR Mug") }
  let!(:payment_method) { create(:check_payment_method) }
  let!(:zone) { create(:zone) }

  context "visitor makes checkout as guest without registration" do
    before(:each) do
      stock_location.stock_items.update_all(count_on_hand: 1)
    end

    context "defaults to use billing address" do
      before do
        add_mug_to_cart
        Spree::Order.last.update_column(:email, "test@example.com")
        click_button "Checkout"
      end

      it "should default checkbox to checked", inaccessible: true do
        expect(find("input#order_use_billing")).to be_checked
      end

      it "should remain checked when used and visitor steps back to address step", js: true do
        fill_in_address
        expect(find("input#order_use_billing")).to be_checked
      end
    end

    # Regression test for #4079
    context "persists state when on address page" do
      before do
        add_mug_to_cart
        click_button "Checkout"
      end

      specify do
        expect(Spree::Order.count).to eq(1)
        expect(Spree::Order.last.state).to eq("address")
      end
    end

    # Regression test for #1596
    context "full checkout" do
      before do
        shipping_method.calculator.update!(preferred_amount: 10)
        mug.shipping_category = shipping_method.shipping_categories.first
        mug.save!
      end

      it "does not break the per-item shipping method calculator", js: true do
        add_mug_to_cart
        click_button "Checkout"
        fill_in "order_email", with: "test@example.com"
        click_button "Continue"
        fill_in_address
        click_button "Save and Continue"
        expect(page).not_to have_content("undefined method `promotion'")
        click_button "Save and Continue"
        expect(page).to have_content("Shipping total: $10.00")
      end
    end

    # Regression test for #4306
    context "free shipping" do
      before do
        add_mug_to_cart
        click_button "Checkout"
        fill_in "order_email", with: "test@example.com"
        click_button "Continue"
      end

      it "should not show 'Free Shipping' when there are no shipments", js: true do
        within("#checkout-summary") do
          expect(page).to_not have_content("Free Shipping")
        end
      end
    end
  end

  # Regression test for #2694 and #4117
  context "doesn't allow bad credit card numbers", js: true do
    before(:each) do
      order = Spree::TestingSupport::OrderWalkthrough.up_to(:delivery)
      allow(order).to receive_messages confirmation_required?: true
      allow(order).to receive_messages(available_payment_methods: [create(:credit_card_payment_method)])

      user = create(:user)
      order.user = user
      order.recalculate

      allow_any_instance_of(Spree::CheckoutController).to receive_messages(current_order: order)
      allow_any_instance_of(Spree::CheckoutController).to receive_messages(spree_current_user: user)
    end

    it "redirects to payment page", inaccessible: true do
      visit spree.checkout_state_path(:delivery)
      click_button "Save and Continue"
      choose "Credit Card"
      fill_in_number("Card Number", "123")
      fill_in_expiration("card_expiry", "04", "2020")
      fill_in "Card Code", with: "123"
      click_button "Save and Continue"
      click_button "Place Order"
      expect(page).to have_content("Bogus Gateway: Forced failure")
      expect(page.current_url).to include("/checkout/payment")
    end
  end

  context "and likes to double click buttons" do
    let!(:user) { create(:user) }

    let!(:order) do
      order = Spree::TestingSupport::OrderWalkthrough.up_to(:delivery)
      allow(order).to receive_messages confirmation_required?: true

      order.reload
      order.user = user
      order.recalculate
      order
    end

    before(:each) do
      allow_any_instance_of(Spree::CheckoutController).to receive_messages(current_order: order)
      allow_any_instance_of(Spree::CheckoutController).to receive_messages(spree_current_user: user)
      allow_any_instance_of(Spree::CheckoutController).to receive_messages(skip_state_validation?: true)
    end

    it "prevents double clicking the payment button on checkout", js: true do
      visit spree.checkout_state_path(:payment)

      # prevent form submit to verify button is disabled
      page.execute_script("$('#checkout_form_payment').submit(function(){return false;})")

      expect(page).not_to have_selector("input.btn[disabled]")
      click_button "Save and Continue"
      expect(page).to have_selector("input.btn[disabled]")
    end

    it "prevents double clicking the confirm button on checkout", js: true do
      order.payments << create(:payment)
      visit spree.checkout_state_path(:confirm)
      click_button "Save and Continue"

      # prevent form submit to verify button is disabled
      page.execute_script("$('#checkout_form_confirm').submit(function(){return false;})")
      expect(page).not_to have_selector("input.btn[disabled]")
      click_button "Place Order"
      expect(page).to have_selector("input.btn[disabled]")
    end
  end

  context "when several payment methods are available" do
    let(:credit_cart_payment) { create(:credit_card_payment_method) }
    let(:check_payment) { create(:check_payment_method) }

    after do
      Capybara.ignore_hidden_elements = true
    end

    before do
      Capybara.ignore_hidden_elements = false
      order = Spree::TestingSupport::OrderWalkthrough.up_to(:delivery)
      allow(order).to receive_messages(available_payment_methods: [check_payment, credit_cart_payment])
      order.user = create(:user)
      order.recalculate

      allow_any_instance_of(Spree::CheckoutController).to receive_messages(current_order: order)
      allow_any_instance_of(Spree::CheckoutController).to receive_messages(spree_current_user: order.user)

      visit spree.checkout_state_path(:payment)
    end

    it "the first payment method should be selected", js: true do
      payment_method_css = "#order_payments_attributes__payment_method_id_"
      expect(find("#{payment_method_css}#{check_payment.id}")).to be_checked
      expect(find("#{payment_method_css}#{credit_cart_payment.id}")).not_to be_checked
    end

    it "the fields for the other payment methods should be hidden", js: true do
      payment_method_css = "#payment_method_"
      expect(find("#{payment_method_css}#{check_payment.id}")).to be_visible
      expect(find("#{payment_method_css}#{credit_cart_payment.id}")).not_to be_visible
    end
  end

  context "user has payment sources", js: true do
    before { Spree::PaymentMethod.all.each(&:destroy) }
    let!(:bogus) { create(:credit_card_payment_method) }
    let(:user) { create(:user) }

    let(:credit_card) do
      create(:credit_card, user_id: user.id, payment_method: bogus, gateway_customer_profile_id: "BGS-WEFWF")
    end

    before do
      order = Spree::TestingSupport::OrderWalkthrough.up_to(:delivery)
      allow(order).to receive_messages(available_payment_methods: [bogus])
      user.wallet.add(credit_card)

      allow_any_instance_of(Spree::CheckoutController).to receive_messages(current_order: order)
      allow_any_instance_of(Spree::CheckoutController).to receive_messages(spree_current_user: user)
      allow_any_instance_of(Spree::OrdersController).to receive_messages(spree_current_user: user)

      visit spree.checkout_state_path(:payment)
    end

    it "selects first source available and customer moves on" do
      expect(find("#use_existing_card_yes")).to be_checked

      expect {
        click_on "Save and Continue"
      }.not_to change { Spree::CreditCard.count }

      click_on "Place Order"
      expect(current_path).to include(spree.order_path(Spree::Order.last))
    end

    it "allows user to enter a new source" do
      choose "use_existing_card_no"

      fill_in "Name on card", with: "Spree Commerce"
      fill_in_number("Card Number", "4111111111111111")
      fill_in_expiration("card_expiry", "04", "2020")
      fill_in "Card Code", with: "123"
      expect {
        click_on "Save and Continue"
      }.to change { Spree::CreditCard.count }.by 1

      click_on "Place Order"
      expect(current_path).to include(spree.order_path(Spree::Order.last))
    end
  end

  # regression for #2921
  context "goes back from payment to add another item", js: true do
    let!(:bag) { create(:product, name: "RoR Bag") }

    it "transit nicely through checkout steps again" do
      add_mug_to_cart
      click_on "Checkout"
      fill_in "order_email", with: "test@example.com"
      click_on "Continue"
      fill_in_address

      click_on "Save and Continue"
      click_on "Save and Continue"
      expect(current_path).to eql(spree.checkout_state_path("payment"))

      visit spree.root_path
      click_link bag.name
      click_button "add-to-cart-button"

      click_on "Checkout"
      click_on "Save and Continue"
      click_on "Save and Continue"
      click_on "Save and Continue"
      click_on "Place Order"

      expect(current_path).to include(spree.order_path(Spree::Order.last))
    end
  end

  context "from payment step customer goes back to cart", js: true do
    before do
      add_mug_to_cart
      click_on "Checkout"
      fill_in "order_email", with: "test@example.com"
      click_on "Continue"
      fill_in_address
      click_on "Save and Continue"
      click_on "Save and Continue"
      expect(current_path).to eql(spree.checkout_state_path("payment"))
    end

    context "and updates line item quantity and try to reach payment page" do
      before do
        visit spree.cart_path
        within ".cart-item-quantity" do
          fill_in first("input")["name"], with: 3
        end

        click_on "Update"
      end

      it "redirects user back to address step" do
        visit spree.checkout_state_path("payment")
        expect(current_path).to eql(spree.checkout_state_path("address"))
      end

      it "updates shipments properly through step address -> delivery transitions" do
        visit spree.checkout_state_path("payment")
        click_on "Save and Continue"
        click_on "Save and Continue"

        expect(Spree::InventoryUnit.count).to eq 3
      end
    end

    context "and adds new product to cart and try to reach payment page" do
      let!(:bag) { create(:product, name: "RoR Bag") }

      before do
        visit spree.root_path
        click_link bag.name
        click_button "add-to-cart-button"
      end

      it "redirects user back to address step" do
        visit spree.checkout_state_path("payment")
        expect(current_path).to eql(spree.checkout_state_path("address"))
      end

      it "updates shipments properly through step address -> delivery transitions" do
        visit spree.checkout_state_path("payment")
        click_on "Save and Continue"
        click_on "Save and Continue"

        expect(Spree::InventoryUnit.count).to eq 2
      end
    end
  end

  context "in coupon promotion, submits coupon along with payment", js: true do
    let!(:promotion) { FactoryBot.create(:promotion, name: "Huhuhu", code: "huhu") }
    let!(:calculator) { Spree::Calculator::FlatPercentItemTotal.create(preferred_flat_percent: "10") }
    let!(:action) { Spree::Promotion::Actions::CreateItemAdjustments.create(calculator: calculator) }

    before do
      promotion.actions << action

      add_mug_to_cart
      click_on "Checkout"

      fill_in "order_email", with: "test@example.com"
      click_on "Continue"
      fill_in_address
      click_on "Save and Continue"
      click_on "Save and Continue"

      expect(current_path).to eql(spree.checkout_state_path("payment"))
    end

    it "makes sure payment reflects order total with discounts" do
      fill_in "Coupon Code", with: promotion.codes.first.value
      click_on "Apply Code"

      expect(page).to have_content(promotion.name)
      expect(page).to have_content("-$2.00")
    end

    context "invalid coupon" do
      it "doesnt create a payment record" do
        fill_in "Coupon Code", with: "invalid"
        click_on "Apply Code"

        expect(page).to have_content(I18n.t("spree.coupon_code_not_found"))
      end
    end

    context "doesn't fill in coupon code input" do
      it "advances just fine" do
        click_on "Save and Continue"
        expect(current_path).to include(spree.checkout_state_path("confirm"))
      end
    end
  end

  context "order has only payment step", js: true do
    before do
      create(:credit_card_payment_method)
      @old_checkout_flow = Spree::Order.checkout_flow
      Spree::Order.class_eval do
        checkout_flow do
          go_to_state :payment
          go_to_state :confirm
        end
      end

      allow_any_instance_of(Spree::Order).to receive_messages email: "spree@commerce.com"

      add_mug_to_cart
      click_on "Checkout"
    end

    after do
      Spree::Order.checkout_flow(&@old_checkout_flow)
    end

    it "goes right payment step and place order just fine" do
      expect(current_path).to eq spree.checkout_state_path("payment")

      choose "Credit Card"
      fill_in "Name on card", with: "Spree Commerce"
      fill_in_number("Card Number", "4111111111111111")
      fill_in_expiration("card_expiry", "04", "2020")
      fill_in "Card Code", with: "123"
      click_button "Save and Continue"

      expect(current_path).to include spree.checkout_state_path("confirm")
      click_button "Place Order"
    end
  end

  context "save my address" do
    before do
      stock_location.stock_items.update_all(count_on_hand: 1)
      add_mug_to_cart
    end

    context "as a guest" do
      before do
        Spree::Order.last.update_column(:email, "test@example.com")
        click_button "Checkout"
      end

      it "should not be displayed" do
        expect(page).to_not have_css("[data-hook=save_user_address]")
      end
    end

    context "as a User" do
      before do
        user = create(:user)
        Spree::Order.last.update_column :user_id, user.id
        allow_any_instance_of(Spree::OrdersController).to receive_messages(spree_current_user: user)
        allow_any_instance_of(Spree::CheckoutController).to receive_messages(spree_current_user: user)
        click_button "Checkout"
      end

      it "should be displayed" do
        expect(page).to have_css("[data-hook=save_user_address]")
      end
    end
  end

  context "when order is completed", js: true do
    let!(:user) { create(:user) }
    let!(:order) { Spree::TestingSupport::OrderWalkthrough.up_to(:delivery) }

    before(:each) do
      allow_any_instance_of(Spree::CheckoutController).to receive_messages(current_order: order)
      allow_any_instance_of(Spree::CheckoutController).to receive_messages(spree_current_user: user)
      allow_any_instance_of(Spree::OrdersController).to receive_messages(spree_current_user: user)

      visit spree.checkout_state_path(:delivery)
      click_button "Save and Continue"
      click_button "Save and Continue"
      click_button "Place Order"
    end

    it "displays a thank you message" do
      expect(page).to have_content(I18n.t("spree.thank_you_for_your_order"))
    end

    it "does not display a thank you message on that order future visits" do
      visit spree.order_path(order)
      expect(page).to_not have_content(I18n.t("spree.thank_you_for_your_order"))
    end
  end

  scenario "associate an uncompleted guest order with user after logging in", js: true do
    user = create(:user, email: "email@person.com", password: "password", password_confirmation: "password")
    add_mug_to_cart

    visit spree.login_path
    fill_in "Email", with: user.email
    fill_in "Password", with: user.password
    click_button "Login"
    click_link "Cart"

    expect(page).to have_text "RoR Mug"
    within("h1") { expect(page).to have_text "Shopping Cart" }

    click_button "Checkout"
    fill_in_address
    click_button "Save and Continue"
    click_button "Save and Continue"
    click_button "Save and Continue"
    click_button "Place Order"

    expect(page).to have_text "Your order has been processed successfully"
    expect(Spree::Order.first.user).to eq user
  end

  scenario "allow a user to register during checkout", js: true do
    add_mug_to_cart
    click_button "Checkout"

    expect(page).to have_text "Registration"

    click_link "Create a new account"

    fill_in "Email", with: "email@person.com"
    fill_in "Password", with: "spree123"
    fill_in "Password Confirmation", with: "spree123"
    click_button "Create"

    expect(page).to have_text "You have signed up successfully."

    fill_in_address

    click_button "Save and Continue"
    click_button "Save and Continue"
    click_button "Save and Continue"
    click_button "Place Order"

    expect(page).to have_text "Your order has been processed successfully"
    expect(Spree::Order.first.user).to eq Spree::User.find_by_email("email@person.com")
  end

  def fill_in_address
    address = "order_bill_address_attributes"

    if ::Spree.solidus_gem_version < Gem::Version.new("3.0.0")
      fill_in "#{address}_firstname", with: "Ryan"
      fill_in "#{address}_lastname", with: "Bigg"
    else
      fill_in "#{address}_name", with: "Ryan Bigg"
    end

    fill_in "#{address}_address1", with: "143 Swan Street"
    fill_in "#{address}_city", with: "Richmond"
    select "United States of America", from: "#{address}_country_id"
    select "Alabama", from: "#{address}_state_id"
    fill_in "#{address}_zipcode", with: "12345"
    fill_in "#{address}_phone", with: "(555) 555-5555"
  end

  def add_mug_to_cart
    visit spree.root_path
    click_link mug.name
    click_button "add-to-cart-button"
  end
end
