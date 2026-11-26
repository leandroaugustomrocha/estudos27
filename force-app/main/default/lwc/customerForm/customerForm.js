import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";

import CUSTOMER_OBJECT from "@salesforce/schema/Customer__c";
import NAME_FIELD from "@salesforce/schema/Customer__c.Name";
import EMAIL_FIELD from "@salesforce/schema/Customer__c.Email__c";
import PHONE_FIELD from "@salesforce/schema/Customer__c.Phone__c";
import POSTAL_CODE_FIELD from "@salesforce/schema/Customer__c.Postal_Code__c";
import STREET_FIELD from "@salesforce/schema/Customer__c.Street__c";
import NUMBER_FIELD from "@salesforce/schema/Customer__c.Address_Number__c";
import COMPLEMENT_FIELD from "@salesforce/schema/Customer__c.Address_Complement__c";
import DISTRICT_FIELD from "@salesforce/schema/Customer__c.District__c";
import CITY_FIELD from "@salesforce/schema/Customer__c.City__c";
import STATE_FIELD from "@salesforce/schema/Customer__c.State__c";

import lookupCep from "@salesforce/apex/CustomerController.lookupCep";
import saveCustomer from "@salesforce/apex/CustomerController.saveCustomer";
import getDocument from "@salesforce/apex/CustomerController.getDocument";

import TITLE_NEW from "@salesforce/label/c.Customer_Form_Title_New";
import TITLE_EDIT from "@salesforce/label/c.Customer_Form_Title_Edit";
import SAVE from "@salesforce/label/c.Customer_Save";
import CANCEL from "@salesforce/label/c.Customer_Cancel";
import SAVED from "@salesforce/label/c.Customer_Saved";
import SAVE_ERROR_TITLE from "@salesforce/label/c.Customer_Save_Error_Title";
import SEARCHING from "@salesforce/label/c.Customer_Searching_Postal_Code";
import DOCUMENT_KEPT_HELP from "@salesforce/label/c.Customer_Document_Kept_Help";
import INVALID_POSTAL_CODE from "@salesforce/label/c.Customer_Invalid_Postal_Code";
import POSTAL_CODE_NOT_FOUND from "@salesforce/label/c.Customer_Postal_Code_Not_Found";
import SERVICE_UNAVAILABLE from "@salesforce/label/c.Customer_Cep_Service_Unavailable";

const RECORD_FIELDS = [
  NAME_FIELD,
  EMAIL_FIELD,
  PHONE_FIELD,
  POSTAL_CODE_FIELD,
  STREET_FIELD,
  NUMBER_FIELD,
  COMPLEMENT_FIELD,
  DISTRICT_FIELD,
  CITY_FIELD,
  STATE_FIELD
];
const EDITABLE_FIELDS = RECORD_FIELDS.map((f) => f.fieldApiName).concat([
  "Document_Input__c"
]);
const POSTAL_CODE_LENGTH = 8;

const onlyDigits = (value) => (value ?? "").replace(/\D/g, "");

/** First readable message of an Apex or LDS error. */
const errorMessage = (error) => {
  const body = error?.body;
  if (Array.isArray(body)) {
    return body.map((item) => item.message).join(", ");
  }
  return body?.message ?? error?.message ?? "";
};

/**
 * Customer create/edit form with postal code lookup (spec 002, REQ-003 to REQ-007,
 * REQ-018, REQ-019, REQ-022, REQ-026). Used by the "Novo cliente" tab and by the
 * "Editar cliente" record action.
 */
export default class CustomerForm extends NavigationMixin(LightningElement) {
  @api recordId;

  labels = {
    titleNew: TITLE_NEW,
    titleEdit: TITLE_EDIT,
    save: SAVE,
    cancel: CANCEL,
    searching: SEARCHING,
    documentKeptHelp: DOCUMENT_KEPT_HELP
  };

  customer = Object.fromEntries(EDITABLE_FIELDS.map((name) => [name, null]));
  isSearching = false;
  isSaving = false;
  postalCodeError;
  postalCodeNotFound = false;
  serviceUnavailable = false;
  cityAndStateFromPostalCode = false;
  currentDocument;
  lastLookedUpPostalCode;

  @wire(getObjectInfo, { objectApiName: CUSTOMER_OBJECT })
  objectInfo;

  @wire(getPicklistValues, {
    recordTypeId: "$defaultRecordTypeId",
    fieldApiName: STATE_FIELD
  })
  statePicklist;

  @wire(getRecord, { recordId: "$recordId", fields: RECORD_FIELDS })
  wiredCustomer({ data, error }) {
    if (data) {
      const loaded = { Document_Input__c: null };
      RECORD_FIELDS.forEach((f) => {
        loaded[f.fieldApiName] = data.fields[f.fieldApiName]?.value ?? null;
      });
      this.customer = loaded;
      this.lastLookedUpPostalCode = onlyDigits(loaded.Postal_Code__c);
      this.cityAndStateFromPostalCode = Boolean(loaded.Postal_Code__c);
    } else if (error) {
      this.showToast("error", SAVE_ERROR_TITLE, errorMessage(error));
    }
  }

  /** REQ-022: Apex returns the document only to whoever registered it and to admins. */
  @wire(getDocument, { customerId: "$recordId" })
  wiredDocument({ data }) {
    this.currentDocument = data ?? undefined;
  }

  get defaultRecordTypeId() {
    return this.objectInfo?.data?.defaultRecordTypeId;
  }

  get fieldLabels() {
    const fields = this.objectInfo?.data?.fields ?? {};
    return Object.fromEntries(
      EDITABLE_FIELDS.map((name) => [name, fields[name]?.label ?? ""])
    );
  }

  get stateOptions() {
    return (this.statePicklist?.data?.values ?? []).map((v) => ({
      label: v.label,
      value: v.value
    }));
  }

  get isNew() {
    return !this.recordId;
  }

  get title() {
    return this.isNew ? this.labels.titleNew : this.labels.titleEdit;
  }

  get documentPlaceholder() {
    return this.currentDocument ?? "";
  }

  get documentHelp() {
    return this.isNew ? "" : this.labels.documentKeptHelp;
  }

  /** REQ-018: city and UF follow the postal code, unless the service is down (REQ-007). */
  get cityAndStateLocked() {
    return this.cityAndStateFromPostalCode && !this.serviceUnavailable;
  }

  get saveDisabled() {
    return this.isSearching || this.isSaving || this.postalCodeNotFound;
  }

  handleChange(event) {
    const fieldName = event.target.dataset.field;
    this.customer = { ...this.customer, [fieldName]: event.detail.value };
  }

  /** REQ-003, REQ-019: lookup as soon as the postal code has 8 digits, without a button. */
  handlePostalCodeChange(event) {
    const value = event.detail.value;
    this.customer = { ...this.customer, Postal_Code__c: value };
    this.postalCodeError = undefined;
    this.postalCodeNotFound = false;
    const digits = onlyDigits(value);
    if (
      digits.length === POSTAL_CODE_LENGTH &&
      digits !== this.lastLookedUpPostalCode
    ) {
      this.lookUp(digits);
    } else if (digits.length === 0) {
      this.cityAndStateFromPostalCode = false;
      this.lastLookedUpPostalCode = undefined;
    }
  }

  /** REQ-005 */
  handlePostalCodeBlur() {
    const digits = onlyDigits(this.customer.Postal_Code__c);
    if (digits.length > 0 && digits.length !== POSTAL_CODE_LENGTH) {
      this.postalCodeError = INVALID_POSTAL_CODE;
    }
  }

  async lookUp(digits) {
    this.isSearching = true;
    this.lastLookedUpPostalCode = digits;
    try {
      this.applyLookup(await lookupCep({ postalCode: digits }));
    } catch (error) {
      this.postalCodeError = errorMessage(error);
    } finally {
      this.isSearching = false;
    }
  }

  applyLookup(result) {
    if (result?.status === "FOUND") {
      // REQ-003: replace the address fields; number and complement are never touched (REQ-004).
      this.customer = {
        ...this.customer,
        Street__c: result.street ?? null,
        District__c: result.district ?? null,
        City__c: result.city ?? null,
        State__c: result.state ?? null
      };
      this.cityAndStateFromPostalCode = true;
      this.serviceUnavailable = false;
    } else if (result?.status === "NOT_FOUND") {
      // REQ-006: saving stays blocked until the postal code is fixed.
      this.postalCodeNotFound = true;
      this.postalCodeError = POSTAL_CODE_NOT_FOUND;
      this.serviceUnavailable = false;
    } else {
      // REQ-007: free every address field for manual entry.
      this.serviceUnavailable = true;
      this.cityAndStateFromPostalCode = false;
      this.showToast("warning", "", SERVICE_UNAVAILABLE);
    }
  }

  async handleSave() {
    const inputs = [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ];
    const allValid = inputs.reduce(
      (valid, input) => input.reportValidity() !== false && valid,
      true
    );
    if (!allValid || this.postalCodeError || this.saveDisabled) {
      return;
    }
    this.isSaving = true;
    try {
      const record = { ...this.customer };
      if (this.recordId) {
        record.Id = this.recordId;
      }
      const savedId = await saveCustomer({ customer: record });
      this.showToast("success", "", SAVED);
      if (this.recordId) {
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        this.dispatchEvent(new CloseActionScreenEvent());
      } else {
        this[NavigationMixin.Navigate]({
          type: "standard__recordPage",
          attributes: {
            recordId: savedId,
            objectApiName: CUSTOMER_OBJECT.objectApiName,
            actionName: "view"
          }
        });
      }
    } catch (error) {
      this.showToast("error", SAVE_ERROR_TITLE, errorMessage(error));
    } finally {
      this.isSaving = false;
    }
  }

  handleCancel() {
    if (this.recordId) {
      this.dispatchEvent(new CloseActionScreenEvent());
      return;
    }
    this.customer = Object.fromEntries(
      EDITABLE_FIELDS.map((name) => [name, null])
    );
    this.postalCodeError = undefined;
    this.postalCodeNotFound = false;
    this.serviceUnavailable = false;
    this.cityAndStateFromPostalCode = false;
    this.lastLookedUpPostalCode = undefined;
  }

  showToast(variant, title, message) {
    this.dispatchEvent(new ShowToastEvent({ variant, title, message }));
  }
}
