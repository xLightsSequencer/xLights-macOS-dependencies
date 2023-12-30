/////////////////////////////////////////////////////////////////////////////
// Name:        wx/valtext.h
// Purpose:     wxTextValidator class
// Author:      Julian Smart
// Modified by: Francesco Montorsi
// Created:     29/01/98
// Copyright:   (c) 1998 Julian Smart
// Licence:     wxWindows licence
/////////////////////////////////////////////////////////////////////////////

#ifndef _WX_VALTEXT_H_
#define _WX_VALTEXT_H_

#include "wx/defs.h"

#if wxUSE_VALIDATORS && (wxUSE_TEXTCTRL || wxUSE_COMBOBOX)

class WXDLLIMPEXP_FWD_BASE wxRegEx;
class WXDLLIMPEXP_FWD_CORE wxTextEntry;

#include "wx/validate.h"
#include "wx/sharedptr.h"

enum wxTextValidatorStyle
{
    wxFILTER_NONE = 0x0,
    wxFILTER_EMPTY = 0x1,
    wxFILTER_ASCII = 0x2,
    wxFILTER_ALPHA = 0x4,
    wxFILTER_ALPHANUMERIC = 0x8,
    wxFILTER_DIGITS = 0x10,
    wxFILTER_NUMERIC = 0x20,
    wxFILTER_INCLUDE_LIST = 0x40,
    wxFILTER_INCLUDE_CHAR_LIST = 0x80,
    wxFILTER_EXCLUDE_LIST = 0x100,
    wxFILTER_EXCLUDE_CHAR_LIST = 0x200,
    wxFILTER_XDIGITS = 0x400,
    wxFILTER_SPACE = 0x800,

    // filter char class (for internal use only)
    wxFILTER_CC = wxFILTER_SPACE|wxFILTER_ASCII|wxFILTER_NUMERIC|
                  wxFILTER_ALPHANUMERIC|wxFILTER_ALPHA|
                  wxFILTER_DIGITS|wxFILTER_XDIGITS
};

// ----------------------------------------------------------------------------
// wxTextEntryValidator: common base class for wxTextValidator & wxNumValidator
// ----------------------------------------------------------------------------
class WXDLLIMPEXP_CORE wxTextEntryValidator : public wxValidator
{
public:
    wxTextEntryValidator() {}
    wxTextEntryValidator(const wxTextEntryValidator& other)
        : wxValidator(other)
    {}

    virtual ~wxTextEntryValidator() {}

    // Override base class method to check whether the window does support
    // this type of validators or not.
    virtual void SetWindow(wxWindow *win) override;

    // returns the error message if the contents of 'str' are invalid.
    virtual wxString IsValid(const wxString& str) const = 0;

protected:
    // Get the text entry of the associated control. Normally shouldn't ever
    // return NULL (and will assert if it does return it) but the caller should
    // still test the return value for safety.
    wxTextEntry *GetTextEntry() const;

    // Events handlers
    void OnText(wxCommandEvent& event);
    void OnPasteText(wxClipboardTextEvent& event);
    void OnValidate(wxValidationStatusEvent& event);
    void OnKillFocus(wxFocusEvent& event);

private:
    // It needs to access our ms_skipTextEvent variable.
    friend class WXDLLIMPEXP_FWD_CORE wxWindowBase;

    // wxWindowBase::InitDialog() will ensure no wxEVT_TEXT event is generated
    // while the dialog/panel is being initialised by setting this to false.
    static bool ms_skipTextEvent;
};

// ----------------------------------------------------------------------------
// wxTextValidator
// ----------------------------------------------------------------------------

class WXDLLIMPEXP_CORE wxTextValidator: public wxTextEntryValidator
{
public:
    wxTextValidator(long style = wxFILTER_NONE, wxString *val = nullptr);
    wxTextValidator(const wxTextValidator& val);

    virtual ~wxTextValidator() = default;

    // Make a clone of this validator (or return nullptr) - currently necessary
    // if you're passing a reference to a validator.
    // Another possibility is to always pass a pointer to a new validator
    // (so the calling code can use a copy constructor of the relevant class).
    virtual wxObject *Clone() const override { return new wxTextValidator(*this); }
    bool Copy(const wxTextValidator& val);

    // Called when the value in the window must be validated.
    // This function can pop up an error message.
    virtual bool Validate(wxWindow *parent) override;

    // Called to transfer data to the window
    virtual bool TransferToWindow() override;

    // Called to transfer data from the window
    virtual bool TransferFromWindow() override;

    // Filter keystrokes
    void OnChar(wxKeyEvent& event);

    // ACCESSORS
    inline long GetStyle() const { return m_validatorStyle; }
    void SetStyle(long style);

    // strings & chars inclusions:
    // ---------------------------

    void SetCharIncludes(const wxString& chars);
    void AddCharIncludes(const wxString& chars);

    void SetIncludes(const wxArrayString& includes);
    void AddInclude(const wxString& include);

    const wxArrayString& GetIncludes() const { return m_includes; }
    wxString GetCharIncludes() const { return m_charIncludes; }

    // strings & chars exclusions:
    // ---------------------------

    void SetCharExcludes(const wxString& chars);
    void AddCharExcludes(const wxString& chars);

    void SetExcludes(const wxArrayString& excludes);
    void AddExclude(const wxString& exclude);

    const wxArrayString& GetExcludes() const { return m_excludes; }
    wxString GetCharExcludes() const { return m_charExcludes; }

    bool HasFlag(wxTextValidatorStyle style) const
        { return (m_validatorStyle & style) != 0; }

    // implementation only
    // --------------------

    // returns the error message if the contents of 'str' are invalid
    virtual wxString IsValid(const wxString& str) const override;

protected:

    bool IsCharIncluded(const wxUniChar& c) const
    {
        return m_charIncludes.find(c) != wxString::npos;
    }

    bool IsCharExcluded(const wxUniChar& c) const
    {
        return m_charExcludes.find(c) != wxString::npos;
    }

    bool IsIncluded(const wxString& str) const
    {
        if ( HasFlag(wxFILTER_INCLUDE_LIST) )
            return m_includes.Index(str) != wxNOT_FOUND;

        // m_includes should be ignored (i.e. return true)
        // if the style is not set.
        return true;
    }

    bool IsExcluded(const wxString& str) const
    {
        return m_excludes.Index(str) != wxNOT_FOUND;
    }

    // returns false if the character is invalid
    bool IsValidChar(const wxUniChar& c) const;

    // These two functions (undocumented now) are kept for compatibility reasons.
    bool ContainsOnlyIncludedCharacters(const wxString& val) const;
    bool ContainsExcludedCharacters(const wxString& val) const;

protected:
    long                 m_validatorStyle;
    wxString*            m_stringValue;
    wxString             m_charIncludes;
    wxString             m_charExcludes;
    wxArrayString        m_includes;
    wxArrayString        m_excludes;

private:
    void OnPaste(wxClipboardTextEvent& event);

    wxDECLARE_NO_ASSIGN_CLASS(wxTextValidator);
    wxDECLARE_DYNAMIC_CLASS(wxTextValidator);
    wxDECLARE_EVENT_TABLE();
};

#if wxUSE_REGEX
// ----------------------------------------------------------------------------
// wxRegexTextValidator declaration
// ----------------------------------------------------------------------------

class WXDLLIMPEXP_CORE wxRegexTextValidator : public wxTextValidator
{
public:
    wxRegexTextValidator(long style = wxFILTER_NONE, wxString* str = nullptr);
    wxRegexTextValidator(const wxString& pattern, const wxString& intent,
                         long style = wxFILTER_NONE, wxString* str = nullptr);

    // default ctor is ok

    // Use one of these functions to initialize the validator if the first
    // constructor was used to create it.
    void SetRegEx(const wxString& pattern, const wxString& intent);
    void SetRegEx(wxSharedPtr<wxRegEx> regex, const wxString& intent);

    virtual wxObject *Clone() const override;

    // Override base class function
    virtual wxString IsValid(const wxString& str) const override;

private:
    wxSharedPtr<wxRegEx>   m_regex;
    wxString               m_intent;

    wxDECLARE_DYNAMIC_CLASS_NO_ASSIGN(wxRegexTextValidator);
};

#endif // wxUSE_REGEX

#endif
  // wxUSE_VALIDATORS && (wxUSE_TEXTCTRL || wxUSE_COMBOBOX)

#endif // _WX_VALTEXT_H_
