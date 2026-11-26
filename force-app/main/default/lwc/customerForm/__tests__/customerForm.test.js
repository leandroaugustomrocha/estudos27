import { createElement } from "lwc";
import CustomerForm from "c/customerForm";
import lookupCep from "@salesforce/apex/CustomerController.lookupCep";
import saveCustomer from "@salesforce/apex/CustomerController.saveCustomer";
import getDocument from "@salesforce/apex/CustomerController.getDocument";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";

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

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

// The navigation stub does not record calls; this one does.
const mockNavigate = jest.fn();
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageReference) {
        mockNavigate(pageReference);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { NavigationMixin };
});

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

const RECORD_ID = "a0X000000000001AAA";
const LOADED_RECORD = {
  fields: {
    Name: { value: "Maria Silva" },
    Email__c: { value: null },
    Phone__c: { value: null },
    Postal_Code__c: { value: "01310-100" },
    Street__c: { value: "Avenida Paulista" },
    Address_Number__c: { value: "1000" },
    Address_Complement__c: { value: "Sala 5" },
    District__c: { value: "Bela Vista" },
    City__c: { value: "São Paulo" },
    State__c: { value: "SP" }
  }
};

/** A promise the test resolves when it wants, to control the order of answers. */
function deferred() {
  let resolve;
  const promise = new Promise((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

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

  // REQ-026, REQ-022, REQ-018 — edit action loads the customer once
  it("loads the customer in edit mode with city and UF locked and the document as placeholder", async () => {
    const element = createForm({ recordId: RECORD_ID });
    getRecord.emit(LOADED_RECORD);
    getDocument.emit("529.982.247-25");
    await flushPromises();

    expect(field(element, "Name").value).toBe("Maria Silva");
    expect(field(element, "Postal_Code__c").value).toBe("01310-100");
    expect(field(element, "City__c").disabled).toBe(true);
    expect(field(element, "Document_Input__c").placeholder).toBe(
      "529.982.247-25"
    );
    expect(field(element, "Document_Input__c").value).toBeNull();
    expect(lookupCep).not.toHaveBeenCalled();
  });

  // REQ-026 — a later LDS emission does not discard what the user typed
  it("keeps typed values when the record is emitted again", async () => {
    const element = createForm({ recordId: RECORD_ID });
    getRecord.emit(LOADED_RECORD);
    await flushPromises();
    await type(element, "Name", "Maria S. Silva");

    getRecord.emit(LOADED_RECORD);
    await flushPromises();

    expect(field(element, "Name").value).toBe("Maria S. Silva");
  });

  // REQ-026 — saving the edit action refreshes the record and the document, then closes
  it("saves an edit with the record Id, refreshes and closes the action", async () => {
    saveCustomer.mockResolvedValue(RECORD_ID);
    const element = createForm({ recordId: RECORD_ID });
    const closeHandler = jest.fn();
    element.addEventListener("close", closeHandler);
    getRecord.emit(LOADED_RECORD);
    getDocument.emit("529.982.247-25");
    await flushPromises();

    saveButton(element).click();
    await flushPromises();

    expect(saveCustomer.mock.calls[0][0].customer.Id).toBe(RECORD_ID);
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: RECORD_ID }
    ]);
    expect(refreshApex).toHaveBeenCalled();
    expect(closeHandler).toHaveBeenCalled();
  });

  // REQ-026 — a new customer opens its record page after saving
  it("navigates to the new customer after saving", async () => {
    saveCustomer.mockResolvedValue("a0X000000000009AAA");
    const element = createForm();
    await type(element, "Name", "Maria");

    saveButton(element).click();
    await flushPromises();

    expect(mockNavigate).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "standard__recordPage",
        attributes: expect.objectContaining({ recordId: "a0X000000000009AAA" })
      })
    );
  });

  // AC-006 / REQ-006 — clicking Save with an unknown postal code does nothing
  it("does not call the server when saving with an unknown postal code", async () => {
    lookupCep.mockResolvedValue({ status: "NOT_FOUND" });
    const element = createForm();
    await type(element, "Name", "Maria");
    await type(element, "Postal_Code__c", "99999999");

    saveButton(element).click();
    await flushPromises();

    expect(saveCustomer).not.toHaveBeenCalled();
  });

  // AC-019 / REQ-018 — adjusted street is kept and sent
  it("keeps a street adjusted after the lookup", async () => {
    lookupCep.mockResolvedValue(PAULISTA);
    saveCustomer.mockResolvedValue("a0X000000000003AAA");
    const element = createForm();
    await type(element, "Name", "Maria");
    await type(element, "Postal_Code__c", "01310100");
    await type(element, "Street__c", "Avenida Paulista (bloco B)");

    saveButton(element).click();
    await flushPromises();

    expect(field(element, "Street__c").value).toBe(
      "Avenida Paulista (bloco B)"
    );
    expect(saveCustomer.mock.calls[0][0].customer.Street__c).toBe(
      "Avenida Paulista (bloco B)"
    );
  });

  // AC-026 / REQ-023 — blank postal code: no lookup, save allowed
  it("saves without postal code and without looking it up", async () => {
    saveCustomer.mockResolvedValue("a0X000000000004AAA");
    const element = createForm();
    await type(element, "Name", "Maria");

    saveButton(element).click();
    await flushPromises();

    expect(lookupCep).not.toHaveBeenCalled();
    expect(saveCustomer).toHaveBeenCalledTimes(1);
    expect(saveCustomer.mock.calls[0][0].customer.Postal_Code__c).toBeNull();
  });

  // REQ-003, REQ-019 — answers arriving out of order: the current postal code wins
  it("ignores the answer of an older lookup", async () => {
    const first = deferred();
    const second = deferred();
    lookupCep
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise);
    const element = createForm();
    await type(element, "Postal_Code__c", "01310100");
    await type(element, "Postal_Code__c", "20040020");

    second.resolve(PIO_X);
    await flushPromises();
    first.resolve(PAULISTA);
    await flushPromises();

    expect(field(element, "Street__c").value).toBe("Praça Pio X");
    expect(field(element, "City__c").value).toBe("Rio de Janeiro");
  });

  // REQ-007 "tente de novo" — retyping the same postal code retries after UNAVAILABLE
  it("retries the same postal code after the service was down", async () => {
    lookupCep
      .mockResolvedValueOnce({ status: "UNAVAILABLE" })
      .mockResolvedValueOnce(PAULISTA);
    const element = createForm();
    await type(element, "Postal_Code__c", "01310100");
    await type(element, "Postal_Code__c", "0131010");
    await type(element, "Postal_Code__c", "01310100");

    expect(lookupCep).toHaveBeenCalledTimes(2);
    expect(field(element, "Street__c").value).toBe("Avenida Paulista");
    expect(field(element, "City__c").disabled).toBe(true);
  });

  // REQ-006 — retyping an unknown postal code checks it again instead of unlocking Save
  it("checks an unknown postal code again when it is retyped", async () => {
    lookupCep.mockResolvedValue({ status: "NOT_FOUND" });
    const element = createForm();
    await type(element, "Postal_Code__c", "99999999");
    await type(element, "Postal_Code__c", "9999999");
    await type(element, "Postal_Code__c", "99999999");

    expect(lookupCep).toHaveBeenCalledTimes(2);
    expect(saveButton(element).disabled).toBe(true);
  });

  // REQ-007 — a failure of the call itself follows the "service down" rule
  it("treats a failed lookup call as service unavailable", async () => {
    lookupCep.mockRejectedValue({ body: { message: "Network error" } });
    const element = createForm();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    await type(element, "Postal_Code__c", "01310100");

    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "c.Customer_Cep_Service_Unavailable"
    );
    expect(field(element, "City__c").disabled).toBe(false);
  });

  // Double submit protection — Save is disabled while looking up
  it("disables Save while the lookup is running", async () => {
    const pending = deferred();
    lookupCep.mockReturnValue(pending.promise);
    const element = createForm();

    await type(element, "Postal_Code__c", "01310100");
    expect(saveButton(element).disabled).toBe(true);

    pending.resolve(PAULISTA);
    await flushPromises();
    expect(saveButton(element).disabled).toBe(false);
  });

  // Cancel — clears the new form and drops a lookup in flight
  it("clears the new form on cancel, even with a lookup in flight", async () => {
    const pending = deferred();
    lookupCep.mockReturnValue(pending.promise);
    const element = createForm();
    await type(element, "Name", "Maria");
    await type(element, "Postal_Code__c", "01310100");

    element.shadowRoot
      .querySelector('lightning-button[data-id="cancel"]')
      .click();
    pending.resolve(PAULISTA);
    await flushPromises();

    expect(field(element, "Name").value).toBeNull();
    expect(field(element, "Street__c").value).toBeNull();
    expect(field(element, "City__c").disabled).toBeFalsy();
  });

  // Cancel — closes the edit action
  it("closes the edit action on cancel", async () => {
    const element = createForm({ recordId: RECORD_ID });
    const closeHandler = jest.fn();
    element.addEventListener("close", closeHandler);
    await flushPromises();

    element.shadowRoot
      .querySelector('lightning-button[data-id="cancel"]')
      .click();

    expect(closeHandler).toHaveBeenCalled();
  });

  // Error bodies may come as an array (LDS/DML)
  it("joins the messages of an error body that is an array", async () => {
    saveCustomer.mockRejectedValue({
      body: [{ message: "Primeiro erro" }, { message: "Segundo erro" }]
    });
    const element = createForm();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);
    await type(element, "Name", "Maria");

    saveButton(element).click();
    await flushPromises();

    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "Primeiro erro, Segundo erro"
    );
  });
});
