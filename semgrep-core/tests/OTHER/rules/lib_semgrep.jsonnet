{
   //old: And: function(arr) { and: arr },
   //trick to emulate variable number of arguments in jsonnet
   //src:  https://groups.google.com/g/jsonnet/c/45DS8Q7zmsM?pli=1
   // 
   And: function(x1, x2, x3=null, x4=null) { and: std.prune([x1,x2,x3,x4]) },
   Or: function(x1, x2, x3=null, x4=null) { or: std.prune([x1,x2,x3,x4]) },
   Not: function(x) { not: x },
   Where: function(x) { where: x },

   basic_rule: function(lang, match) {
    rules: [
    {
      id: 'rule_template_id',
      match: match,
      message: 'rule_template_message',
      languages: [lang],
      severity: 'ERROR',
    },
    ],
  }

}
