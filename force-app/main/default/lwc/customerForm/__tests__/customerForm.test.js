import { createElement } from "lwc";
import CustomerForm from "c/customerForm";
import lookupCep from "@salesforce/apex/CustomerController.lookupCep";
import saveCustomer from "@salesforce/apex/CustomerController.saveCustomer";

// Spec 002 — customer form (AC-003 to AC-007, AC-018 to AC-020, AC-029).

jest.mock(
  "@salesforce/apex/CustomerController.lookupCep",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CustomerController.saveCustomer",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CustomerController.getDocument",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "lightning/actions",
  () => ({
    CloseActionScreenEvent: class CloseActionScreenEvent extends CustomEvent {
      constructor() {
        super("close");
      }
    }
  }),
  { virtual: true }
);

const PAULISTA = {
  status: "FOUND",
  street: "Avenida Paulista",
  district: "Bela Vista",
  city: "São Paulo",
  state: "SP"
};
const PIO_X = {
  status: "FOUND",
  street: "Praça Pio X",
  district: "Centro",
  city: "Rio de Janeiro",
  state: "RJ"
};

// Waits for pending promises (Apex mocks) and the re-render; standard pattern in LWC Jest tests.
const flushPromises = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

function createForm(props = {}) {
  const element = createElement("c-customer-form", { is: CustomerForm });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function field(element, apiName) {
  return element.shadowRoot.querySelector(`[data-field="${apiName}"]`);
}

async function type(element, apiName, value) {
  const input = field(element, apiName);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await flushPromises();
}

function saveButton(element) {
  return element.shadowRoot.querySelector('lightning-button[data-id="save"]');
}

describe("c-customer-form", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // AC-003, AC-018 / REQ-003, REQ-018
  it("looks up the address as soon as the postal code has 8 digits and locks city and UF", async () => {
    lookupCep.mockResolvedValue(PAULISTA);
    const element = createForm();
    await type(element, "Postal_Code__c", "01310-10");
    expect(lookupCep).not.toHaveBeenCalled();

    await type(element, "Postal_Code__c", "01310-100");

    expect(lookupCep).toHaveBeenCalledWith({ postalCode: "01310100" });
    expect(field(element, "Street__c").value).toBe("Avenida Paulista");
    expect(field(element, "District__c").value).toBe("Bela Vista");
    expect(field(element, "City__c").value).toBe("São Paulo");
    expect(field(element, "State__c").value).toBe("SP");
    expect(field(element, "City__c").disabled).toBe(true);
    expect(field(element, "State__c").disabled).toBe(true);
    expect(field(element, "Street__c").disabled).toBeFalsy();
    expect(field(element, "District__c").disabled).toBeFalsy();
  });

  // AC-018 / REQ-003 — values typed before the lookup are replaced
  it("overwrites street and city typed before the lookup", async () => {
    lookupCep.mockResolvedValue(PAULISTA);
    const element = createForm();
    await type(element, "Street__c", "Rua X");
    await type(element, "City__c", "Campinas");

    await type(element, "Postal_Code__c", "01310100");

    expect(field(element, "Street__c").value).toBe("Avenida Paulista");
    expect(field(element, "City__c").value).toBe("São Paulo");
  });

  // AC-004 / REQ-004
  it("never touches number and complement", async () => {
    lookupCep.mockResolvedValue(PAULISTA);
    const element = createForm();
    await type(element, "Address_Number__c", "1000");
    await type(element, "Address_Complement__c", "Sala 5");

    await type(element, "Postal_Code__c", "01310100");

    expect(field(element, "Address_Number__c").value).toBe("1000");
    expect(field(element, "Address_Complement__c").value).toBe("Sala 5");
  });

  // AC-005 / REQ-005
  it("shows the format message without calling the service", async () => {
    const element = createForm();
    await type(element, "Postal_Code__c", "0131010");
    field(element, "Postal_Code__c").dispatchEvent(new CustomEvent("blur"));
    await flushPromises();

    expect(lookupCep).not.toHaveBeenCalled();
    const error = element.shadowRoot.querySelector(
      '[data-id="postal-code-error"]'
    );
    expect(error.textContent).toBe("c.Customer_Invalid_Postal_Code");
  });

  // AC-006 / REQ-006
  it("blocks saving while the postal code is not found", async () => {
    lookupCep.mockResolvedValue({ status: "NOT_FOUND" });
    const element = createForm();

    await type(element, "Postal_Code__c", "99999-999");

    const error = element.shadowRoot.querySelector(
      '[data-id="postal-code-error"]'
    );
    expect(error.textContent).toBe("c.Customer_Postal_Code_Not_Found");
    expect(saveButton(element).disabled).toBe(true);
  });

  // AC-007 / REQ-007
  it("unlocks the address and warns when the service is down", async () => {
    lookupCep.mockResolvedValue({ status: "UNAVAILABLE" });
    const element = createForm();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    await type(element, "Postal_Code__c", "01310100");

    expect(field(element, "City__c").disabled).toBe(false);
    expect(field(element, "State__c").disabled).toBe(false);
    expect(saveButton(element).disabled).toBe(false);
    expect(toastHandler).toHaveBeenCalled();
    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "c.Customer_Cep_Service_Unavailable"
    );
  });

  // AC-020 / REQ-019
  it("looks up again and replaces the address when the postal code changes", async () => {
    lookupCep.mockResolvedValueOnce(PAULISTA).mockResolvedValueOnce(PIO_X);
    const element = createForm();
    await type(element, "Postal_Code__c", "01310100");
    await type(element, "Address_Number__c", "1000");

    await type(element, "Postal_Code__c", "20040-020");

    expect(lookupCep).toHaveBeenCalledTimes(2);
    expect(field(element, "Street__c").value).toBe("Praça Pio X");
    expect(field(element, "City__c").value).toBe("Rio de Janeiro");
    expect(field(element, "State__c").value).toBe("RJ");
    expect(field(element, "Address_Number__c").value).toBe("1000");
  });

  // AC-029 / REQ-026 — same form for the "Novo cliente" tab and the "Editar cliente" action
  it("shows the new or edit title depending on the record", async () => {
    const newForm = createForm();
    await flushPromises();
    expect(
      newForm.shadowRoot.querySelector('[data-id="title"]').textContent
    ).toBe("c.Customer_Form_Title_New");
    expect(field(newForm, "Document_Input__c").required).toBe(true);

    const editForm = createForm({ recordId: "a0X000000000001AAA" });
    await flushPromises();
    expect(
      editForm.shadowRoot.querySelector('[data-id="title"]').textContent
    ).toBe("c.Customer_Form_Title_Edit");
    expect(field(editForm, "Document_Input__c").required).toBe(false);
  });

  // REQ-001, REQ-017 — save sends the typed customer, including the document input
  it("saves the customer and confirms with a toast", async () => {
    saveCustomer.mockResolvedValue("a0X000000000002AAA");
    const element = createForm();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);
    await type(element, "Name", "Maria Silva");
    await type(element, "Document_Input__c", "529.982.247-25");

    saveButton(element).click();
    await flushPromises();

    expect(saveCustomer).toHaveBeenCalledTimes(1);
    const sent = saveCustomer.mock.calls[0][0].customer;
    expect(sent.Name).toBe("Maria Silva");
    expect(sent.Document_Input__c).toBe("529.982.247-25");
    expect(sent.Id).toBeUndefined();
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("success");
  });

  // REQ-006, REQ-012 — server errors are shown to the user, not swallowed
  it("shows the server message when saving fails", async () => {
    saveCustomer.mockRejectedValue({
      body: { message: "Informe um e-mail válido." }
    });
    const element = createForm();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);
    await type(element, "Name", "Maria");

    saveButton(element).click();
    await flushPromises();

    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("error");
    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "Informe um e-mail válido."
    );
  });
});
